"""Shared free-tier usage limiter for managed AI endpoints.

A single source of truth for metering so every AI endpoint (managed chat and
the Document AI features) enforces the SAME per-identity daily cap and the SAME
Pro-bypass rule. Verified-Pro users (active purchase token) are unlimited.

The actual counting is delegated to a pluggable backend
(``app.services.ai.usage_backend``): in-memory for a single instance, or Redis
for correct metering across multiple instances. The choice is driven by
``settings.AI_METER_BACKEND``; the Pro-bypass rule below is identical regardless
of backend.
"""

from datetime import date
from typing import Optional

from fastapi import Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.entitlement import Entitlement
from app.models.user import User
from app.services.ai.usage_backend import UsageBackend, build_backend

# Sentinel returned as "remaining" when the caller is unlimited (Pro).
UNLIMITED = -1

# Lazily constructed so importing this module never touches Redis; the backend
# is built on first use (and rebuildable via reset()).
_backend: Optional[UsageBackend] = None


def _get_backend() -> UsageBackend:
    global _backend
    if _backend is None:
        _backend = build_backend()
    return _backend


def check_and_increment(key: str) -> tuple[bool, int]:
    """Increment today's counter for ``key``.

    Returns ``(allowed, count)`` where ``allowed`` is False once the daily cap
    is reached (in which case the counter is NOT incremented).
    """
    today = date.today().isoformat()
    return _get_backend().check_and_increment(key, settings.AI_FREE_DAILY_LIMIT, today)


def check_and_increment_tiered(key: str, limit: int) -> tuple[bool, int]:
    """Like ``check_and_increment`` but honours a caller-supplied per-tier limit.

    Used by endpoints that resolve the entitlement token to a tier-specific
    daily quota (free / basic / pro) via ``billing.quota_tiers.get_quota``.
    """
    today = date.today().isoformat()
    return _get_backend().check_and_increment(key, limit, today)


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
    """Clear all counters and rebuild the backend. Intended for tests."""
    global _backend
    if _backend is not None:
        _backend.clear()
    _backend = None
