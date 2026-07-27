"""Admin usage dashboard (Part 5.8) + Webhook DLQ (Part 7.2).

Aggregate, enterprise-facing metrics for operators: how many users, teams,
templates, and active Pro entitlements exist, plus the current metering config.
This is intentionally separate from the per-request health dashboard.

Access is gated by a shared secret: set ``ADMIN_API_TOKEN`` and send it as the
``X-Admin-Token`` header. When the token is unset the endpoints report 503
(disabled) so a misconfigured deployment never exposes metrics unauthenticated.

Enhancement-Based Masterplan additions:
- E7.2 Webhook DLQ + replay (scaffold, in-memory + DB count, extensible to Redis)
- E8.1 per-team quota visibility via usage? -> kept in usage_dashboard for now
"""

import secrets
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.database import get_db
from app.models.entitlement import Entitlement
from app.models.team import SharedTemplate, Team, TeamMember
from app.models.user import User
from app.models.webhook import Webhook

router = APIRouter()


async def require_admin_token(
    x_admin_token: str | None = Header(default=None, alias="X-Admin-Token"),
) -> None:
    """Guard: require a valid admin token, or fail with 503/401."""
    if not settings.ADMIN_API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin dashboard is not configured on the server.",
        )
    # Constant-time comparison to avoid leaking the token via timing.
    if not x_admin_token or not secrets.compare_digest(
        x_admin_token, settings.ADMIN_API_TOKEN
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing admin token.",
        )


class UsageDashboardResponse(BaseModel):
    total_users: int
    active_users: int
    total_teams: int
    total_team_members: int
    total_shared_templates: int
    active_entitlements: int
    active_webhooks: int
    ai_free_daily_limit: int
    ai_basic_daily_limit: int
    meter_backend: str


class WebhookDLQItem(BaseModel):
    id: str
    url: str
    events: list[str]
    active: bool
    created_at: datetime
    reason: str = "delivery_failed_placeholder"


class WebhookDLQResponse(BaseModel):
    dlq_count: int
    items: list[WebhookDLQItem]
    note: str


class WebhookReplayResponse(BaseModel):
    id: str
    status: str
    message: str


async def _count(db: AsyncSession, column) -> int:
    """Return COUNT(column) as a plain int (portable across dialects)."""
    result = await db.execute(select(func.count()).select_from(column))
    return int(result.scalar_one() or 0)


@router.get(
    "/admin/usage",
    response_model=UsageDashboardResponse,
    dependencies=[Depends(require_admin_token)],
    tags=["Admin"],
)
async def usage_dashboard(db: AsyncSession = Depends(get_db)):
    """Aggregate usage / enterprise metrics for operators."""
    total_users = await _count(db, User)
    active_users = int(
        (
            await db.execute(
                select(func.count()).select_from(User).where(User.is_active.is_(True))
            )
        ).scalar_one()
        or 0
    )
    total_teams = await _count(db, Team)
    total_members = await _count(db, TeamMember)
    total_templates = await _count(db, SharedTemplate)

    # Active entitlements: valid, non-free. Expiry is evaluated in Python via
    # is_active() so the same rule applies everywhere.
    ents = (
        await db.execute(select(Entitlement).where(Entitlement.valid.is_(True)))
    ).scalars().all()
    active_entitlements = sum(1 for e in ents if e.is_active())

    # Webhooks count for platform health
    active_webhooks = int(
        (await db.execute(select(func.count()).select_from(Webhook).where(Webhook.active.is_(True)))).scalar_one()
        or 0
    )

    return UsageDashboardResponse(
        total_users=total_users,
        active_users=active_users,
        total_teams=total_teams,
        total_team_members=total_members,
        total_shared_templates=total_templates,
        active_entitlements=active_entitlements,
        active_webhooks=active_webhooks,
        ai_free_daily_limit=settings.AI_FREE_DAILY_LIMIT,
        ai_basic_daily_limit=settings.AI_BASIC_DAILY_LIMIT,
        meter_backend=settings.AI_METER_BACKEND,
    )


# ---- Webhook DLQ (E7.2) ----------------------------------------------------
# Minimal scaffold: lists inactive webhooks as DLQ candidates and allows admin
# to replay/enable. Full delivery attempt log (Redis/DB) is a follow-up:
# - Add WebhookDeliveryAttempt model (webhook_id, event_type, payload, status, attempts)
# - Store attempts in Redis list capped 100 per webhook
# - This endpoint then reads from that store.

@router.get(
    "/admin/webhooks/dlq",
    response_model=WebhookDLQResponse,
    dependencies=[Depends(require_admin_token)],
    tags=["Admin"],
)
async def webhook_dlq(db: AsyncSession = Depends(get_db)):
    """List webhook deliveries that are currently dead-lettered.

    V1 scaffold: returns inactive webhooks as DLQ proxies. The full
    delivery-attempt log (E7.2) will replace the in-memory placeholder with
    a persistent store once `WebhookDeliveryAttempt` is added.
    """
    # For now: inactive webhooks are considered DLQ; in future, query attempt log
    inactive = (
        await db.execute(select(Webhook).where(Webhook.active.is_(False)).order_by(Webhook.created_at.desc()).limit(100))
    ).scalars().all()

    items = [
        WebhookDLQItem(
            id=str(w.id),
            url=w.url,
            events=w.event_list,
            active=w.active,
            created_at=w.created_at,
            reason="inactive_or_delivery_failed",
        )
        for w in inactive
    ]

    return WebhookDLQResponse(
        dlq_count=len(items),
        items=items,
        note="V1 scaffold: inactive webhooks listed as DLQ. Full delivery attempt log is a follow-up (see ENHANCEMENT_BASED_MASTERPLAN.md E7.2).",
    )


@router.post(
    "/admin/webhooks/{webhook_id}/replay",
    response_model=WebhookReplayResponse,
    dependencies=[Depends(require_admin_token)],
    tags=["Admin"],
)
async def webhook_replay(webhook_id: str, db: AsyncSession = Depends(get_db)):
    """Replay / re-enable a DLQ webhook.

    V1: re-activates the webhook (sets active=True) so future events resume.
    V2: will actually re-deliver the last failed payload with HMAC signing +
    exponential backoff (see E5.4 + E7.2).
    """
    from uuid import UUID

    try:
        uid = UUID(webhook_id)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid webhook id format")

    webhook = (await db.execute(select(Webhook).where(Webhook.id == uid))).scalar_one_or_none()
    if not webhook:
        raise HTTPException(status_code=404, detail="Webhook not found")

    webhook.active = True
    await db.flush()

    return WebhookReplayResponse(
        id=str(webhook.id),
        status="requeued",
        message="Webhook re-activated. Full payload replay will be implemented with delivery log (E7.2 V2).",
    )


@router.get(
    "/admin/webhooks/stats",
    dependencies=[Depends(require_admin_token)],
    tags=["Admin"],
)
async def webhook_stats(db: AsyncSession = Depends(get_db)) -> dict[str, Any]:
    """Lightweight stats for the health dashboard (E7.2 + E5.4)."""
    total = await _count(db, Webhook)
    active = int((await db.execute(select(func.count()).select_from(Webhook).where(Webhook.active.is_(True)))).scalar_one() or 0)
    inactive = total - active
    return {
        "total_webhooks": total,
        "active_webhooks": active,
        "inactive_or_dlq": inactive,
        "delivery_model": "scaffold_v1 — delivery log pending (see ENHANCEMENT_BASED_MASTERPLAN.md)",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

