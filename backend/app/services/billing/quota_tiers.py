"""Per-plan AI quota tiers (Part 8.1 — Production Hardening + E8.1 per-team quota).

Instead of a single binary (free = 15/day, Pro = unlimited), this introduces a
tiered quota system where each subscription plan gets its own daily AI limit:

- **free**     → ``AI_FREE_DAILY_LIMIT`` (default 15)
- **basic**    → ``AI_BASIC_DAILY_LIMIT`` (default 100)
- **monthly**  → unlimited
- **yearly**   → unlimited
- **lifetime** → unlimited

E8.1 — Per-team quota: a team can define ``ai_daily_quota`` which is shared
among its members when they act in team context (X-Team-Id header). Only an
authenticated member of that team may draw on its pool; an explicit header
from anyone else is rejected with 403. The stored quota is capped at
``AI_TEAM_DAILY_QUOTA_MAX``. The quota resolution order is:
1. If team_id provided (caller is a member) and team has ai_daily_quota -> that limit
2. Else entitlement tier quota (free/basic/unlimited)

The ``quota_for`` function resolves the entitlement tier to a concrete daily
limit (or ``None`` for unlimited). The usage limiter can then pass this limit
to the metering backend instead of the hardcoded ``AI_FREE_DAILY_LIMIT``.

This is additive: existing endpoints that call ``is_pro`` still work (Pro tiers
return unlimited), but new callers can use ``get_quota`` for finer-grained
control.
"""

from __future__ import annotations

import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.exceptions import AuthorizationError
from app.models.entitlement import Entitlement

# Tiers that get unlimited AI access (no daily cap).
_UNLIMITED_TIERS = frozenset({"monthly", "yearly", "lifetime"})
# Paid plans — may use the advanced (more expensive) model.
PAID_TIERS = frozenset({"basic"}) | _UNLIMITED_TIERS


def quota_for_tier(tier: str) -> Optional[int]:
    """Return the daily AI quota for a tier, or ``None`` for unlimited.

    ``None`` means the caller should bypass metering entirely (Pro).
    """
    if tier in _UNLIMITED_TIERS:
        return None  # unlimited
    if tier == "basic":
        return settings.AI_BASIC_DAILY_LIMIT
    # Everything else (including "free" and unknown tiers) gets the free cap.
    return settings.AI_FREE_DAILY_LIMIT


async def get_quota(db: AsyncSession, token: Optional[str]) -> tuple[str, Optional[int]]:
    """Resolve an entitlement token to ``(tier, daily_limit)``.

    Returns ``("free", AI_FREE_DAILY_LIMIT)`` when the token is absent/invalid.
    Returns ``("monthly", None)`` (etc.) when the token is valid + active.

    The ``daily_limit`` is ``None`` when the tier is unlimited.
    """
    if not token:
        return "free", settings.AI_FREE_DAILY_LIMIT
    try:
        ent = (
            await db.execute(
                select(Entitlement).where(Entitlement.purchase_token == token)
            )
        ).scalar_one_or_none()
        if ent and ent.is_active():
            return ent.tier, quota_for_tier(ent.tier)
        return "free", settings.AI_FREE_DAILY_LIMIT
    except Exception:  # noqa: BLE001 - DB issues must not break AI
        return "free", settings.AI_FREE_DAILY_LIMIT


async def get_team_quota(db: AsyncSession, team_id: Optional[uuid.UUID]) -> Optional[int]:
    """Resolve a team to its daily quota (E8.1).

    Returns None if team has no quota configured (use user tier).
    Returns int if team has ai_daily_quota set.
    """
    if not team_id:
        return None
    try:
        from app.models.team import Team  # local import to avoid cycle

        team = (await db.execute(select(Team).where(Team.id == team_id))).scalar_one_or_none()
        if team and team.ai_daily_quota is not None:
            return min(team.ai_daily_quota, settings.AI_TEAM_DAILY_QUOTA_MAX)
        return None
    except Exception:  # noqa: BLE001
        return None


def parse_team_header(value: Optional[str]) -> Optional[uuid.UUID]:
    """Parse an ``X-Team-Id`` header; None when absent or malformed."""
    if not value:
        return None
    try:
        return uuid.UUID(value)
    except (ValueError, TypeError, AttributeError):
        return None


async def require_team_member(
    db: AsyncSession, team_id: uuid.UUID, user_id: Optional[uuid.UUID]
) -> None:
    """403 unless ``user_id`` is an authenticated member of ``team_id``."""
    from app.services.team.team_service import get_membership  # avoid cycle

    if user_id is None or await get_membership(db, team_id, user_id) is None:
        raise AuthorizationError("Not a member of this team")


async def get_quota_with_team(
    db: AsyncSession,
    token: Optional[str],
    team_id: Optional[uuid.UUID] = None,
    user_id: Optional[uuid.UUID] = None,
) -> tuple[str, Optional[int], str]:
    """Combined quota resolution: team quota overrides user tier when present.

    The team pool is only available to a member of the team (``user_id``);
    anyone else gets 403.

    Returns (tier, limit, source) where source is "team", "entitlement", or "free".
    """
    if team_id:
        await require_team_member(db, team_id, user_id)
        team_limit = await get_team_quota(db, team_id)
        if team_limit is not None:
            return "team", team_limit, "team"

    tier, limit = await get_quota(db, token)
    source = "entitlement" if token else "free"
    return tier, limit, source


def validate_receipt_fields(product_id: str, purchase_token: str) -> list[str]:
    """Pre-flight validation before calling the Play Developer API.

    Returns a list of error strings (empty = valid). This catches obvious
    client-side spoofing / malformed tokens before spending a network call.
    """
    errors: list[str] = []
    if not purchase_token or len(purchase_token) < 20:
        errors.append("purchase_token too short or empty (minimum 20 chars)")
    if len(purchase_token) > 2000:
        errors.append("purchase_token exceeds maximum length (2000 chars)")
    if not product_id:
        errors.append("product_id is required")
    elif product_id not in {
        settings.PRODUCT_MONTHLY,
        settings.PRODUCT_YEARLY,
        settings.PRODUCT_LIFETIME,
    }:
        errors.append(f"Unknown product_id: {product_id!r}")
    # Tokens are base64 URL-safe; check for obvious injection characters.
    if purchase_token and any(c in purchase_token for c in (' ', '\n', '\t', '<', '>')):
        errors.append("purchase_token contains invalid characters")
    return errors
