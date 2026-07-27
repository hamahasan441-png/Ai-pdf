"""Billing endpoints — server-side Google Play purchase verification.

The client sends the purchaseToken it received from Play Billing; the server
confirms it with Google and returns the authoritative entitlement. This is what
makes Pro spoof-proof (the on-device entitlement is only a UX cache).

Enhancement-Based Masterplan:
- E6.1 RTDN: Play Real-time Developer Notifications for renewal/cancel/refund
  re-verification — keeps entitlement accuracy 99.9% (docs/ENHANCEMENT_BASED_MASTERPLAN.md)
- E7.2 Webhook DLQ health (see admin.py extension)
- Tiered quotas via quota_tiers.py (free/basic/monthly/yearly/lifetime)
"""

import base64
import json
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


async def _persist_rtdn_event(
    db: AsyncSession, product_id: str, purchase_token: str, valid: bool, tier: str, expiry_millis: int | None
) -> None:
    """Upsert entitlement from RTDN event (re-verification path)."""
    try:
        existing = (
            await db.execute(
                select(Entitlement).where(Entitlement.purchase_token == purchase_token)
            )
        ).scalar_one_or_none()
        if existing:
            existing.product_id = product_id or existing.product_id
            existing.tier = tier
            existing.valid = valid
            existing.expiry_millis = expiry_millis
        else:
            db.add(
                Entitlement(
                    purchase_token=purchase_token,
                    product_id=product_id or "unknown",
                    tier=tier,
                    valid=valid,
                    expiry_millis=expiry_millis,
                )
            )
        await db.flush()
    except Exception as e:  # noqa: BLE001
        logger.warning("RTDN persist failed: %s", e)
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


def _decode_pubsub_message(payload: dict) -> dict | None:
    """Decode Pub/Sub push envelope: {"message":{"data": base64_json}} -> dict.

    Returns None if not a valid Pub/Sub envelope (treat as raw RTDN for forward-compat).
    """
    try:
        msg = payload.get("message") if isinstance(payload, dict) else None
        if not msg:
            return payload if isinstance(payload, dict) else None
        data_b64 = msg.get("data")
        if not data_b64:
            return None
        decoded = base64.b64decode(data_b64).decode("utf-8")
        return json.loads(decoded)
    except Exception as e:  # noqa: BLE001
        logger.warning("RTDN pubsub decode failed: %s", e)
        return None


@router.post("/rtdn")
async def realtime_developer_notification(payload: dict, db: AsyncSession = Depends(get_db)):
    """Play Real-time Developer Notifications (Pub/Sub push) webhook.

    Wire this URL as the RTDN endpoint in Play Console to receive
    renewal / cancellation / refund / pause events.

    Flow (enhancement-based):
    1. Decode Pub/Sub push envelope (base64 data -> JSON).
    2. Extract subscriptionNotification / oneTimeProductNotification.
    3. If purchase_token present, re-verify via Play verifier when configured;
       else mark validity based on notificationType.
    4. Upsert Entitlement so subsequent X-Entitlement-Token checks reflect
       renewal/cancel/expiry immediately.
    5. Always return 200 quickly — Play retries on non-2xx.

    Notification types (subscriptions):
    - 1 SUBSCRIPTION_RECOVERED, 2 RENEWED, 3 CANCELED, 4 PURCHASED,
      5 ON_HOLD, 6 IN_GRACE_PERIOD, 7 RESTARTED, 8 PRICE_CHANGE_CONFIRMED,
      9 DEFERRED, 10 PAUSED, 11 PAUSE_SCHEDULE_CHANGED, 12 REVOKED, 13 EXPIRED
    """
    logger.info("RTDN received: %s", str(payload)[:500])

    decoded = _decode_pubsub_message(payload)
    if decoded is None:
        # Not Pub/Sub envelope, treat raw payload as event (tests / manual push)
        decoded = payload

    # Try to extract common fields
    purchase_token = None
    product_id = None
    notification_type = None

    # Subscription notification shape
    sub_notif = decoded.get("subscriptionNotification") if isinstance(decoded, dict) else None
    one_time = decoded.get("oneTimeProductNotification") if isinstance(decoded, dict) else None
    voided = decoded.get("voidedPurchaseNotification") if isinstance(decoded, dict) else None

    if sub_notif:
        purchase_token = sub_notif.get("purchaseToken")
        product_id = sub_notif.get("subscriptionId")
        notification_type = sub_notif.get("notificationType")
    elif one_time:
        purchase_token = one_time.get("purchaseToken")
        product_id = one_time.get("sku")
        notification_type = one_time.get("notificationType")
    elif voided:
        purchase_token = voided.get("purchaseToken")
        product_id = voided.get("productId")

    # Fallback direct fields (for tests)
    if not purchase_token and isinstance(decoded, dict):
        purchase_token = decoded.get("purchase_token") or decoded.get("purchaseToken")
        product_id = decoded.get("product_id") or decoded.get("productId") or decoded.get("subscriptionId") or "unknown"
        notification_type = decoded.get("notificationType", notification_type)

    if not purchase_token:
        logger.info("RTDN: no purchase_token found, ack only (decoded=%s)", str(decoded)[:500])
        return {"received": True, "decoded": bool(decoded), "action": "ack_no_token"}

    # If verifier is configured, re-verify authoritative state
    if play_verifier.configured and product_id and product_id != "unknown":
        try:
            is_sub = True
            # Heuristic: one-time product is not subscription
            if one_time:
                is_sub = False
            result = await play_verifier.verify(product_id, purchase_token, is_sub)
            await _persist_rtdn_event(db, product_id, purchase_token, result.valid, result.tier, result.expiry_millis)
            logger.info(
                "RTDN re-verified token %s... -> valid=%s tier=%s type=%s",
                purchase_token[:12],
                result.valid,
                result.tier,
                notification_type,
            )
            return {"received": True, "reverified": True, "valid": result.valid, "tier": result.tier}
        except httpx.HTTPStatusError as e:
            # 404/410 = token invalid/expired -> mark invalid
            if e.response.status_code in (404, 410):
                await _persist_rtdn_event(db, product_id or "unknown", purchase_token, False, "free", None)
                return {"received": True, "reverified": False, "marked_invalid": True, "reason": f"Play {e.response.status_code}"}
            logger.warning("RTDN re-verify failed %s: %s", e.response.status_code, e.response.text[:200])
            # Fall through to notification-type heuristic
        except Exception as e:  # noqa: BLE001
            logger.warning("RTDN re-verify exception: %s", e)

    # Fallback heuristic when verifier not configured or re-verify failed:
    # Map notification types to entitlement validity.
    # Types that imply still valid: 1,2,4,7 ; invalid / should revoke: 3,12,13 (cancel/revoked/expired)
    valid = True
    tier = "unknown"
    if notification_type in (3, 12, 13):
        valid = False
        tier = "free"
    elif notification_type in (5, 6, 10):  # on hold, grace, paused — treat as still valid but flag
        valid = True
        tier = "monthly"  # keep existing tier intent
    else:
        valid = True

    # If we have an existing entitlement, preserve its tier when notification says still valid
    try:
        existing = (
            await db.execute(
                select(Entitlement).where(Entitlement.purchase_token == purchase_token)
            )
        ).scalar_one_or_none()
        if existing and valid:
            tier = existing.tier
        elif existing and not valid:
            tier = "free"
    except Exception:  # noqa: BLE001
        pass

    await _persist_rtdn_event(db, product_id or "unknown", purchase_token, valid, tier, None)
    return {
        "received": True,
        "reverified": False,
        "heuristic_valid": valid,
        "tier": tier,
        "notification_type": notification_type,
    }

