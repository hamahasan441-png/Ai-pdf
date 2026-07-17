"""Billing endpoints — server-side Google Play purchase verification.

The client sends the purchaseToken it received from Play Billing; the server
confirms it with Google and returns the authoritative entitlement. This is what
makes Pro spoof-proof (the on-device entitlement is only a UX cache).
"""

import logging

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.models.entitlement import Entitlement
from app.services.billing.play_verifier import play_verifier

logger = logging.getLogger(__name__)

router = APIRouter()


class VerifyRequest(BaseModel):
    product_id: str
    purchase_token: str
    is_subscription: bool = True


class VerifyResponse(BaseModel):
    valid: bool
    tier: str
    expiry_millis: int | None = None


async def _persist(db: AsyncSession, req: "VerifyRequest", result) -> None:
    """Upsert the verified entitlement keyed by purchase token. Best-effort:
    a persistence failure must not break the verification response."""
    try:
        existing = (
            await db.execute(
                select(Entitlement).where(Entitlement.purchase_token == req.purchase_token)
            )
        ).scalar_one_or_none()
        if existing:
            existing.product_id = req.product_id
            existing.tier = result.tier
            existing.valid = result.valid
            existing.expiry_millis = result.expiry_millis
        else:
            db.add(
                Entitlement(
                    purchase_token=req.purchase_token,
                    product_id=req.product_id,
                    tier=result.tier,
                    valid=result.valid,
                    expiry_millis=result.expiry_millis,
                )
            )
        await db.flush()
    except Exception as e:  # noqa: BLE001
        logger.warning("Entitlement persist failed: %s", e)
        await db.rollback()


@router.post("/verify", response_model=VerifyResponse)
async def verify_purchase(req: VerifyRequest, db: AsyncSession = Depends(get_db)):
    """Verify a Play purchase/subscription token and return the entitlement."""
    if not play_verifier.configured:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Purchase verification is not configured on the server.",
        )
    if not req.product_id or not req.purchase_token:
        raise HTTPException(status_code=422, detail="product_id and purchase_token are required")

    try:
        result = await play_verifier.verify(
            req.product_id, req.purchase_token, req.is_subscription
        )
    except httpx.HTTPStatusError as e:
        logger.warning("Play verify failed: %s %s", e.response.status_code, e.response.text[:200])
        # 404/410 from Play means the token is invalid/expired -> not entitled.
        if e.response.status_code in (404, 410):
            return VerifyResponse(valid=False, tier="free", expiry_millis=None)
        raise HTTPException(status_code=502, detail="Play verification service error")
    except Exception as e:  # noqa: BLE001
        logger.exception("Play verify error")
        raise HTTPException(status_code=502, detail=f"Verification error: {e}")

    await _persist(db, req, result)
    return VerifyResponse(
        valid=result.valid, tier=result.tier, expiry_millis=result.expiry_millis
    )


@router.post("/rtdn")
async def realtime_developer_notification(payload: dict):
    """Play Real-time Developer Notifications (Pub/Sub push) webhook.

    Wire this URL as the RTDN endpoint in Play Console to receive
    renewal / cancellation / refund events. Currently acknowledges receipt;
    persist + re-verify the affected purchase in a follow-up once entitlements
    are stored per user.
    """
    logger.info("RTDN received: %s", str(payload)[:300])
    return {"received": True}
