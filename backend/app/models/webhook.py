"""Webhook subscription model (Part 7.2 — Developer Platform).

Enterprise users register HTTPS endpoints to receive push notifications when
events happen (AI completions, document indexing, team changes). Each
subscription specifies a target URL and the set of event types it cares about.

Security:
- A shared ``secret`` is generated at registration and included in a HMAC
  signature header (``X-AI-PDF-Signature``) on every delivery so the receiver
  can verify authenticity.
- Subscriptions are scoped to the owning user (``owner_id``).
- Disabled subscriptions (``active=False``) are kept for audit but stop
  receiving deliveries.
"""

import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base

# Supported event types — registry pattern so new events are additive.
EVENT_TYPES = frozenset({
    "ai.chat.complete",
    "ai.summarize.complete",
    "ai.suggest_edits.complete",
    "document.indexed",
    "team.member.added",
    "team.member.removed",
    "api_key.created",
    "api_key.revoked",
})


def generate_webhook_secret() -> str:
    """Generate a 32-byte URL-safe secret for HMAC signing."""
    return secrets.token_urlsafe(32)


def compute_signature(payload: str, secret: str) -> str:
    """HMAC-SHA256 signature of a payload given the subscription secret."""
    return hmac.HMAC(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()


class Webhook(Base):
    """A webhook subscription registered by a user."""

    __tablename__ = "webhooks"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    url: Mapped[str] = mapped_column(String(2048), nullable=False)
    # Comma-separated event types (e.g. "ai.chat.complete,document.indexed").
    events: Mapped[str] = mapped_column(Text, nullable=False)
    # Shared secret for HMAC-SHA256 delivery signature verification.
    secret: Mapped[str] = mapped_column(String(64), nullable=False)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    @property
    def event_list(self) -> list[str]:
        return [e.strip() for e in self.events.split(",") if e.strip()]

    def subscribes_to(self, event_type: str) -> bool:
        return event_type in self.event_list and self.active
