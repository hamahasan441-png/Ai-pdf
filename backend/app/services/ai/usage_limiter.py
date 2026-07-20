"""Shared free-tier usage limiter for managed AI endpoints.

A single source of truth for metering so every AI endpoint (managed chat and
the Document AI features) enforces the SAME per-identity daily cap and the SAME
Pro-bypass rule. Verified-Pro users (active purchase token) are unlimited.

NOTE: the counter is in-memory and per-process — it resets on restart and is
not shared across instances. This is fine for a single instance / early stage.
For multi-instance production, back ``_usage`` with Redis (already a project
dependency) keyed identically, and keep the Pro bypass unchanged.
"""

from datetime import date
from typing import Optional

from fastapi import Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.entitlement import Entitlement
from app.models.user import User

# identity -> (yyyy-mm-dd, count). Swap for Redis in production.
_usage: dict[str, tuple[str, int]] = {}

# Sentinel returned as "remaining" when the caller is unlimited (Pro).
UNLIMITED = -1


def check_and_increment(key: str) -> tuple[bool, int]:
    """Increment today's counter for ``key``.

    Returns ``(allowed, count)`` where ``allowed`` is False once the daily cap
    is reached (in which case the counter is NOT incremented).
    """
    today = date.today().isoformat()
    day, count = _usage.get(key, (today, 0))
    if day != today:
        day, count = today, 0
    if count >= settings.AI_FREE_DAILY_LIMIT:
        return False, count
    _usage[key] = (today, count + 1)
    return True, count + 1


async def is_pro(db: AsyncSession, token: Optional[str]) -> bool:
    """True if the X-Entitlement-Token maps to an active verified purchase."""
    if not token:
        return False
    try:
        ent = (
            await db.execute(
                select(Entitlement).where(Entitlement.purchase_token == token)
            )
        ).scalar_one_or_none()
        return bool(ent and ent.is_active())
    except Exception:  # noqa: BLE001 - DB issues must not break AI
        return False


def identity_for(user: Optional[User], request: Request) -> str:
    """Stable metering identity: user id if logged in, else client IP."""
    if user is not None:
        return str(user.id)
    return request.client.host if request.client else "anon"


def reset() -> None:
    """Clear all counters. Intended for tests."""
    _usage.clear()
