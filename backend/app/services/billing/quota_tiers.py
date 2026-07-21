"""Per-plan AI quota tiers (Part 8.1 — Production Hardening).

Instead of a single binary (free = 15/day, Pro = unlimited), this introduces a
tiered quota system where each subscription plan gets its own daily AI limit:

- **free**     → ``AI_FREE_DAILY_LIMIT`` (default 15)
- **basic**    → ``AI_BASIC_DAILY_LIMIT`` (default 100)
- **monthly**  → unlimited
- **yearly**   → unlimited
- **lifetime** → unlimited

The ``quota_for`` function resolves the entitlement tier to a concrete daily
limit (or ``None`` for unlimited). The usage limiter can then pass this limit
to the metering backend instead of the hardcoded ``AI_FREE_DAILY_LIMIT``.

This is additive: existing endpoints that call ``is_pro`` still work (Pro tiers
return unlimited), but new callers can use ``get_quota`` for finer-grained
control.
"""

from __future__ import annotations

from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.entitlement import Entitlement

# Tiers that get unlimited AI access (no daily cap).
_UNLIMITED_TIERS = frozenset({"monthly", "yearly", "lifetime"})


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
