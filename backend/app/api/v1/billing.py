"""Billing endpoints — server-side Google Play purchase verification.

The client sends the purchaseToken it received from Play Billing; the server
confirms it with Google and returns the authoritative entitlement. This is what
makes Pro spoof-proof (the on-device entitlement is only a UX cache).

Enhancement-Based Masterplan:
- E6.1 RTDN: Play Real-time Developer Notifications for renewal/cancel/refund
  re-verification — keeps entitlement accuracy 99.9% (docs/MASTERPLAN.md)
- E7.2 Webhook DLQ health (see admin.py extension)
- Tiered quotas via quota_tiers.py (free/basic/monthly/yearly/lifetime)
"""

import base64
import json
import logging

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.database import get_db
from app.models.entitlement import Entitlement
from app.services.auth.id_token import (
    GOOGLE_ISSUERS,
    GOOGLE_JWKS_URL,
    IdTokenKeysUnavailable,
    InvalidIdToken,
    verify_id_token,
)
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


async def _require_pubsub_push(authorization: str | None) -> None:
    """Authenticate a Pub/Sub push request (fail closed).

    The push subscription must attach a Google-signed OIDC token. We verify
    its signature against Google's JWKS, that ``aud`` is RTDN_PUSH_AUDIENCE
    and that it was minted for RTDN_PUSH_SERVICE_ACCOUNT (verified email).
    When either setting is blank the endpoint rejects everything.
    """
    audience = settings.RTDN_PUSH_AUDIENCE.strip()
    service_account = settings.RTDN_PUSH_SERVICE_ACCOUNT.strip()
    if not audience or not service_account:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="RTDN push authentication is not configured on the server.",
        )
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing push token")
    try:
        claims = await verify_id_token(
            authorization[7:],
            jwks_url=GOOGLE_JWKS_URL,
            audiences=[audience],
            issuers=GOOGLE_ISSUERS,
        )
    except IdTokenKeysUnavailable:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Google keys unavailable")
    except InvalidIdToken:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid push token")
    if claims.get("email") != service_account or claims.get("email_verified") not in (True, "true"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Push token from unexpected sender")


@router.post("/rtdn")
async def realtime_developer_notification(
    payload: dict,
    authorization: str | None = Header(None, alias="Authorization"),
    db: AsyncSession = Depends(get_db),
):
    """Play Real-time Developer Notifications (Pub/Sub push) webhook.

    Wire this URL as the RTDN endpoint in Play Console to receive
    renewal / cancellation / refund / pause events. The Pub/Sub push
    subscription must be authenticated (OIDC token, see _require_pubsub_push).

    Flow:
    1. Authenticate the push (401/403 for forged or unauthenticated calls).
    2. Decode Pub/Sub push envelope (base64 data -> JSON).
    3. Extract the purchase token + product id. A notification never changes
       an entitlement by itself: the entitlement is set ONLY from the result
       of re-verifying the token with the Play Developer API.
    4. Unknown products are acknowledged without any change.
    5. Return 2xx once handled; transient verification failures return 5xx so
       Pub/Sub retries.

    Notification types (subscriptions):
    - 1 SUBSCRIPTION_RECOVERED, 2 RENEWED, 3 CANCELED, 4 PURCHASED,
      5 ON_HOLD, 6 IN_GRACE_PERIOD, 7 RESTARTED, 8 PRICE_CHANGE_CONFIRMED,
      9 DEFERRED, 10 PAUSED, 11 PAUSE_SCHEDULE_CHANGED, 12 REVOKED, 13 EXPIRED
    """
    await _require_pubsub_push(authorization)

    decoded = _decode_pubsub_message(payload)
    if decoded is None:
        # Not Pub/Sub envelope, treat raw payload as event (manual push)
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

    # Fallback direct fields
    if not purchase_token and isinstance(decoded, dict):
        purchase_token = decoded.get("purchase_token") or decoded.get("purchaseToken")
        product_id = decoded.get("product_id") or decoded.get("productId") or decoded.get("subscriptionId")
        notification_type = decoded.get("notificationType", notification_type)

    if not purchase_token or not isinstance(purchase_token, str):
        logger.info("RTDN: no purchase_token found, ack only")
        return {"received": True, "decoded": bool(decoded), "action": "ack_no_token"}

    known_products = {settings.PRODUCT_MONTHLY, settings.PRODUCT_YEARLY, settings.PRODUCT_LIFETIME}
    if product_id not in known_products:
        logger.info("RTDN: unknown product %r, ack without change", product_id)
        return {"received": True, "action": "ignored_unknown_product"}

    if not play_verifier.configured:
        # Without the authoritative Play check we must not touch entitlements.
        # 503 makes Pub/Sub redeliver once verification is configured.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Purchase verification is not configured on the server.",
        )

    is_sub = product_id != settings.PRODUCT_LIFETIME
    try:
        result = await play_verifier.verify(product_id, purchase_token, is_sub)
    except httpx.HTTPStatusError as e:
        # 404/410 from Play = token invalid/expired -> authoritative "not entitled".
        if e.response.status_code in (404, 410):
            await _persist_rtdn_event(db, product_id, purchase_token, False, "free", None)
            return {"received": True, "reverified": True, "valid": False, "tier": "free"}
        logger.warning("RTDN re-verify failed %s: %s", e.response.status_code, e.response.text[:200])
        raise HTTPException(status_code=502, detail="Play verification service error")
    except Exception as e:  # noqa: BLE001
        logger.warning("RTDN re-verify exception: %s", e)
        raise HTTPException(status_code=502, detail="Play verification error")

    await _persist_rtdn_event(db, product_id, purchase_token, result.valid, result.tier, result.expiry_millis)
    logger.info(
        "RTDN re-verified token %s... -> valid=%s tier=%s type=%s",
        purchase_token[:12],
        result.valid,
        result.tier,
        notification_type,
    )
    return {"received": True, "reverified": True, "valid": result.valid, "tier": result.tier}
