"""Webhook delivery with HMAC signing + retry + DLQ logging — E5.4 + E7.2.

Design:
- For each webhook that subscribes to event_type, POST JSON payload to webhook.url
- Headers: X-AI-PDF-Signature = HMAC-SHA256(payload JSON, secret), X-AI-PDF-Event = event_type
- Retry: 3 attempts exponential backoff 1s, 2s, 4s (configurable, non-blocking via background task)
- Log each final failure/success to WebhookDeliveryAttempt for admin DLQ visibility
- On repeated failures (5+ consecutive failures), webhook remains active but appears in DLQ;
  admin can replay via POST /admin/webhooks/{id}/replay which re-activates.

Integration: call `enqueue_delivery(db, event_type, payload, owner_id)` from AI endpoints
(e.g. after ai.chat.complete). For now it's synchronous best-effort to avoid adding Celery;
in production this would be a background task / Redis queue.
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import uuid

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.webhook import Webhook, WebhookDeliveryAttempt, compute_signature

logger = logging.getLogger(__name__)

_MAX_RETRIES = 3
_BACKOFF_BASE = 1.0  # seconds, exponential
_TIMEOUT = 8.0  # seconds per attempt


async def _send_one(webhook: Webhook, event_type: str, payload: Dict[str, Any]) -> tuple[bool, int | None, str | None]:
    """Send one webhook delivery attempt with HMAC signing."""
    payload_str = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)
    signature = compute_signature(payload_str, webhook.secret)

    headers = {
        "Content-Type": "application/json",
        "X-AI-PDF-Signature": signature,
        "X-Webhook-Signature": signature,  # alias for compat (E5.4)
        "X-AI-PDF-Event": event_type,
        "User-Agent": "AI-PDF-Webhooks/1.0",
    }

    for attempt in range(1, _MAX_RETRIES + 1):
        try:
            async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
                resp = await client.post(webhook.url, content=payload_str, headers=headers)
                if 200 <= resp.status_code < 300:
                    return True, resp.status_code, None
                # Retry on 5xx, not on 4xx (except 429)
                if resp.status_code >= 500 or resp.status_code == 429:
                    if attempt < _MAX_RETRIES:
                        await asyncio.sleep(_BACKOFF_BASE * (2 ** (attempt - 1)))
                        continue
                # Non-retriable or final attempt failed
                return False, resp.status_code, f"HTTP {resp.status_code}: {resp.text[:300]}"
        except httpx.RequestError as e:
            err = f"RequestError: {e}"
            if attempt < _MAX_RETRIES:
                await asyncio.sleep(_BACKOFF_BASE * (2 ** (attempt - 1)))
                continue
            return False, None, err
        except Exception as e:  # noqa: BLE001
            return False, None, f"Exception: {e}"

    return False, None, "Max retries exceeded"


async def deliver_event(
    db: AsyncSession,
    event_type: str,
    payload: Dict[str, Any],
    owner_id: Optional[uuid.UUID] = None,
    webhook_id: Optional[uuid.UUID] = None,
) -> List[WebhookDeliveryAttempt]:
    """Deliver event_type to matching webhooks, log attempts, return logs.

    If webhook_id provided, deliver only to that webhook (for replay).
    If owner_id provided, limit to that owner's webhooks.
    """
    # Find matching webhooks
    if webhook_id:
        result = await db.execute(select(Webhook).where(Webhook.id == webhook_id))
        webhooks = [w for w in result.scalars().all() if w.active]
    else:
        q = select(Webhook).where(Webhook.active.is_(True))
        if owner_id:
            q = q.where(Webhook.owner_id == owner_id)
        all_hooks = (await db.execute(q)).scalars().all()
        webhooks = [w for w in all_hooks if w.subscribes_to(event_type)]

    attempts: List[WebhookDeliveryAttempt] = []
    for wh in webhooks:
        success, status_code, error = await _send_one(wh, event_type, payload)
        attempt = WebhookDeliveryAttempt(
            webhook_id=wh.id,
            event_type=event_type,
            payload_snippet=json.dumps(payload)[:500],
            status_code=status_code,
            success=success,
            attempts=_MAX_RETRIES if not success else 1,
            error=error,
        )
        db.add(attempt)
        attempts.append(attempt)
        if not success:
            logger.warning(
                "Webhook delivery failed webhook=%s event=%s status=%s error=%s",
                wh.id,
                event_type,
                status_code,
                error,
            )
        else:
            logger.info("Webhook delivered webhook=%s event=%s", wh.id, event_type)

    if attempts:
        await db.flush()
    return attempts


async def replay_failed(webhook_id: uuid.UUID, db: AsyncSession) -> WebhookDeliveryAttempt | None:
    """Replay last failed attempt for webhook_id (admin)."""
    last = (
        await db.execute(
            select(WebhookDeliveryAttempt)
            .where(WebhookDeliveryAttempt.webhook_id == webhook_id)
            .order_by(WebhookDeliveryAttempt.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if not last:
        return None

    # Reconstruct minimal payload from snippet (if snippet is valid JSON, else empty)
    try:
        payload = json.loads(last.payload_snippet) if last.payload_snippet else {}
    except Exception:
        payload = {"replay_of": str(last.id), "event_type": last.event_type}

    # Deliver to that specific webhook
    wh = (await db.execute(select(Webhook).where(Webhook.id == webhook_id))).scalar_one_or_none()
    if not wh:
        return None

    success, status_code, error = await _send_one(wh, last.event_type, payload)
    new_attempt = WebhookDeliveryAttempt(
        webhook_id=wh.id,
        event_type=last.event_type,
        payload_snippet=last.payload_snippet,
        status_code=status_code,
        success=success,
        attempts=1,
        error=error,
    )
    db.add(new_attempt)
    await db.flush()
    return new_attempt
