"""Admin usage dashboard (Part 5.8).

Aggregate, enterprise-facing metrics for operators: how many users, teams,
templates, and active Pro entitlements exist, plus the current metering config.
This is intentionally separate from the per-request health dashboard.

Access is gated by a shared secret: set ``ADMIN_API_TOKEN`` and send it as the
``X-Admin-Token`` header. When the token is unset the endpoints report 503
(disabled) so a misconfigured deployment never exposes metrics unauthenticated.
"""

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.database import get_db
from app.models.entitlement import Entitlement
from app.models.team import SharedTemplate, Team, TeamMember
from app.models.user import User

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
    ai_free_daily_limit: int
    meter_backend: str


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

    return UsageDashboardResponse(
        total_users=total_users,
        active_users=active_users,
        total_teams=total_teams,
        total_team_members=total_members,
        total_shared_templates=total_templates,
        active_entitlements=active_entitlements,
        ai_free_daily_limit=settings.AI_FREE_DAILY_LIMIT,
        meter_backend=settings.AI_METER_BACKEND,
    )
