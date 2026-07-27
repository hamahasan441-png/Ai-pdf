"""Paywall A/B analytics endpoints — E6.3A Phase 6.

Tracks paywall exposures and conversions per variant for CVR measurement.

Endpoints:
- POST /billing/paywall/exposure — log exposure (variant A/B shown)
- POST /billing/paywall/conversion — log conversion (plan purchased)
- POST /billing/paywall/trial — log trial start
- GET /admin/paywall/stats — admin aggregates exposure vs conversion per variant (gated by ADMIN_API_TOKEN)

Security:
- Exposure endpoint is public (no auth required for anonymous, but optional auth for logged-in)
- Conversion/trial require auth (user must be logged in to purchase)
- Admin stats gated by X-Admin-Token

Design matches paywall_ab_service.dart client: trackExposure() calls /exposure, trackConversion(plan) calls /conversion.
"""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Header
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user, get_optional_user
from app.api.v1.admin import require_admin_token
from app.db.database import get_db
from app.models.paywall_event import PaywallEvent
from app.models.user import User

router = APIRouter(prefix="/billing/paywall", tags=["Billing"])


class ExposureRequest(BaseModel):
    variant: str = Field(..., description="Variant A or B")
    # Optional for anonymous: client can send without auth
    plan: Optional[str] = None


class ConversionRequest(BaseModel):
    variant: str = Field(..., description="Variant A or B")
    plan: str = Field(..., description="monthly, yearly, lifetime")
    event_type: str = Field("conversion", description="conversion or trial_start")


class EventResponse(BaseModel):
    id: str
    variant: str
    event_type: str
    plan: Optional[str]
    created_at: datetime


@router.post("/exposure", response_model=EventResponse)
async def log_exposure(
    request: ExposureRequest,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Log paywall exposure (variant shown) — public, optional auth."""
    variant = request.variant.strip().upper()
    if variant not in ("A", "B"):
        variant = "A"  # default to A if invalid

    event = PaywallEvent(
        owner_id=user.id if user else None,
        variant=variant,
        event_type="exposure",
        plan=request.plan,
    )
    db.add(event)
    await db.flush()
    return EventResponse(
        id=str(event.id),
        variant=event.variant,
        event_type=event.event_type,
        plan=event.plan,
        created_at=event.created_at,
    )


@router.post("/conversion", response_model=EventResponse)
async def log_conversion(
    request: ConversionRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Log paywall conversion (plan purchased) — requires auth."""
    variant = request.variant.strip().upper()
    if variant not in ("A", "B"):
        variant = "A"
    event_type = request.event_type.strip().lower()
    if event_type not in ("conversion", "trial_start"):
        event_type = "conversion"

    event = PaywallEvent(
        owner_id=user.id,
        variant=variant,
        event_type=event_type,
        plan=request.plan,
    )
    db.add(event)
    await db.flush()
    return EventResponse(
        id=str(event.id),
        variant=event.variant,
        event_type=event.event_type,
        plan=event.plan,
        created_at=event.created_at,
    )


@router.post("/trial", response_model=EventResponse)
async def log_trial(
    request: ExposureRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Log trial start — requires auth."""
    variant = request.variant.strip().upper()
    if variant not in ("A", "B"):
        variant = "A"

    event = PaywallEvent(
        owner_id=user.id,
        variant=variant,
        event_type="trial_start",
        plan=request.plan,
    )
    db.add(event)
    await db.flush()
    return EventResponse(
        id=str(event.id),
        variant=event.variant,
        event_type=event.event_type,
        plan=event.plan,
        created_at=event.created_at,
    )


@router.get("/stats", dependencies=[Depends(require_admin_token)])
async def paywall_stats(db: AsyncSession = Depends(get_db)):
    """Admin aggregates: exposure vs conversion per variant for CVR measurement."""
    # Exposure per variant
    exposures = (
        await db.execute(
            select(PaywallEvent.variant, func.count())
            .where(PaywallEvent.event_type == "exposure")
            .group_by(PaywallEvent.variant)
        )
    ).all()

    conversions = (
        await db.execute(
            select(PaywallEvent.variant, PaywallEvent.plan, func.count())
            .where(PaywallEvent.event_type == "conversion")
            .group_by(PaywallEvent.variant, PaywallEvent.plan)
        )
    ).all()

    trials = (
        await db.execute(
            select(PaywallEvent.variant, func.count())
            .where(PaywallEvent.event_type == "trial_start")
            .group_by(PaywallEvent.variant)
        )
    ).all()

    exp_dict = {row[0]: row[1] for row in exposures}
    trial_dict = {row[0]: row[1] for row in trials}
    # conversions per variant+plan
    conv_dict = {}
    for variant, plan, count in conversions:
        if variant not in conv_dict:
            conv_dict[variant] = {}
        conv_dict[variant][plan] = count

    # Calculate CVR
    cvr = {}
    for variant in ["A", "B"]:
        exp = exp_dict.get(variant, 0)
        conv_total = sum(conv_dict.get(variant, {}).values())
        cvr[variant] = {
            "exposure": exp,
            "conversions_total": conv_total,
            "conversions_by_plan": conv_dict.get(variant, {}),
            "trials": trial_dict.get(variant, 0),
            "cvr": round(conv_total / exp * 100, 2) if exp > 0 else 0,
            "trial_cvr": round(trial_dict.get(variant, 0) / exp * 100, 2) if exp > 0 else 0,
        }

    return {
        "variants": cvr,
        "note": "E6.3A Paywall A/B analytics — exposure vs conversion per variant for CVR measurement. Variant A: monthly emphasis (yearly best value) vs B: lifetime emphasis.",
    }
