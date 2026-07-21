"""API Key model (Part 7.1 — Developer Platform).

Allows users (and optionally teams) to create long-lived API keys for
programmatic access. The key itself is shown once at creation and never stored
in cleartext — only its SHA-256 hash is persisted so a database leak cannot
expose valid credentials.

Security rules:
- Keys are scoped to the creating user (``owner_id``).
- An optional ``team_id`` associates the key with a team for visibility in
  the admin dashboard; it does NOT grant access to other team members' data.
- Keys can be revoked (soft-delete: ``revoked_at`` is set, lookups skip it).
- ``last_used_at`` is updated on each successful authentication so stale keys
  can be identified.
"""

import hashlib
import secrets
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base

# Prefix makes keys visually identifiable and grep-able in logs/configs.
_KEY_PREFIX = "aipdf_"
_KEY_BYTES = 32  # 256-bit random


def generate_api_key() -> tuple[str, str]:
    """Generate a new API key and its SHA-256 hash.

    Returns ``(plaintext_key, key_hash)``. The plaintext is shown once to the
    user; the hash is what we store and compare against on each request.
    """
    raw = secrets.token_urlsafe(_KEY_BYTES)
    plaintext = f"{_KEY_PREFIX}{raw}"
    key_hash = hashlib.sha256(plaintext.encode()).hexdigest()
    return plaintext, key_hash


def hash_key(plaintext: str) -> str:
    """Hash a plaintext key for lookup (constant-time safe via DB query)."""
    return hashlib.sha256(plaintext.encode()).hexdigest()


class ApiKey(Base):
    """A long-lived bearer token for programmatic access."""

    __tablename__ = "api_keys"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    team_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        Uuid(as_uuid=True), nullable=True
    )
    # Human label for the key (e.g. "CI pipeline", "webhook server").
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    # SHA-256 of the full plaintext key. Unique + indexed for fast lookup.
    key_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    # Prefix of the plaintext (first 8 chars) for display in the list UI.
    key_prefix: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    last_used_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    revoked_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    @property
    def is_active(self) -> bool:
        return self.revoked_at is None
