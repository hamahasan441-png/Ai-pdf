"""Webhook subscription endpoints (Part 7.2 — Developer Platform).

Users register HTTPS endpoints to receive event notifications. The shared secret
is returned at creation (shown once) and used by the receiver to verify the
HMAC-SHA256 signature in the ``X-AI-PDF-Signature`` header on each delivery.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.db.database import get_db
from app.models.user import User
from app.models.webhook import EVENT_TYPES, Webhook, generate_webhook_secret
from app.schemas.webhook import (
    WebhookCreateRequest,
    WebhookCreateResponse,
    WebhookEventTypesResponse,
    WebhookResponse,
)

router = APIRouter(prefix="/webhooks", tags=["Webhooks"])

_MAX_WEBHOOKS_PER_USER = 20


@router.get("/event-types", response_model=WebhookEventTypesResponse)
async def list_event_types():
    """Return the list of supported event types."""
    return WebhookEventTypesResponse(event_types=sorted(EVENT_TYPES))


@router.post("", response_model=WebhookCreateResponse, status_code=201)
async def create_webhook(
    request: WebhookCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Register a new webhook subscription. The secret is shown ONLY here."""
    # Validate event types
    invalid = set(request.events) - EVENT_TYPES
    if invalid:
        raise HTTPException(
            status_code=422,
            detail=f"Unknown event types: {', '.join(sorted(invalid))}",
        )

    # Cap per-user
    existing = (
        await db.execute(select(Webhook).where(Webhook.owner_id == user.id))
    ).scalars().all()
    if len(existing) >= _MAX_WEBHOOKS_PER_USER:
        raise HTTPException(
            status_code=409, detail=f"Maximum {_MAX_WEBHOOKS_PER_USER} webhooks reached"
        )

    secret = generate_webhook_secret()
    webhook = Webhook(
        owner_id=user.id,
        url=str(request.url),
        events=",".join(request.events),
        secret=secret,
    )
    db.add(webhook)
    await db.flush()

    return WebhookCreateResponse(
        id=str(webhook.id),
        url=webhook.url,
        events=webhook.event_list,
        secret=secret,
        active=webhook.active,
        created_at=webhook.created_at,
    )


@router.get("", response_model=list[WebhookResponse])
async def list_webhooks(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all webhook subscriptions for the authenticated user."""
    webhooks = (
        await db.execute(
            select(Webhook)
            .where(Webhook.owner_id == user.id)
            .order_by(Webhook.created_at.desc())
        )
    ).scalars().all()
    return [
        WebhookResponse(
            id=str(w.id),
            url=w.url,
            events=w.event_list,
            active=w.active,
            created_at=w.created_at,
        )
        for w in webhooks
    ]


@router.delete("/{webhook_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_webhook(
    webhook_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete (deactivate) a webhook subscription."""
    webhook = (
        await db.execute(
            select(Webhook).where(Webhook.id == webhook_id, Webhook.owner_id == user.id)
        )
    ).scalar_one_or_none()
    if webhook is None:
        raise HTTPException(status_code=404, detail="Webhook not found")
    await db.delete(webhook)
    return None
