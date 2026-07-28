"""API Key model (Part 7.1 — Developer Platform + E7.1 Scopes).

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
- E7.1 — Scopes: each key carries a comma-separated allowlist of capabilities
  (e.g. ai:read, forms:write). The enforcement helper ``has_scope`` checks
  membership so endpoints can gate access without touching the auth flow.
"""

import hashlib
import secrets
import uuid
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base

# Prefix makes keys visually identifiable and grep-able in logs/configs.
_KEY_PREFIX = "aipdf_"
_KEY_BYTES = 32  # 256-bit random

# E7.1 — Allowed scopes, additive design.
API_KEY_SCOPES = frozenset(
    {
        "ai:read",
        "ai:write",
        "forms:read",
        "forms:write",
        "documents:read",
        "documents:write",
        "teams:read",
        "teams:write",
        "webhooks:read",
        "webhooks:write",
        "api_keys:read",
        "api_keys:write",
        "admin:read",
    }
)

# Default scopes granted when none specified — full access, backward-compatible.
DEFAULT_SCOPES = frozenset(
    {
        "ai:read",
        "ai:write",
        "forms:read",
        "forms:write",
        "documents:read",
        "documents:write",
        "teams:read",
        "webhooks:read",
        "webhooks:write",
        "api_keys:read",
    }
)


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
    # E7.1 — Comma-separated scopes (e.g. "ai:read,forms:write").
    scopes: Mapped[str] = mapped_column(Text, default=",".join(sorted(DEFAULT_SCOPES)))
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

    @property
    def scope_list(self) -> list[str]:
        return [s.strip() for s in (self.scopes or "").split(",") if s.strip()]

    def has_scope(self, required: str) -> bool:
        return required in self.scope_list

