"""Document sync model — E8.2 Cloud Sync Opt-In (Enhancement-Based Masterplan).

Opt-in encrypted cloud sync for annotation persistence. The client encrypts
the annotation JSON locally (Fernet, same as profile) and uploads only the
ciphertext. The server never sees plaintext annotations.

Design:
- Each record is scoped to owner_id + file_hash (hash of original file path/content)
- encrypted_blob is opaque TEXT (client-side Fernet ciphertext)
- device_id optional for conflict tracking
- last_modified for last-write-wins + revision history preserved client-side
- deleted flag for soft-delete

This is additive: no existing tables modified, new table only.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base


class DocumentSync(Base):
    """Encrypted annotation sync record (client-side encrypted)."""

    __tablename__ = "document_sync"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # Hash of file path or content (client computes, e.g. SHA256 of file)
    file_hash: Mapped[str] = mapped_column(String(128), index=True, nullable=False)
    # Original file name for UI (optional, not encrypted for listing)
    file_name: Mapped[str | None] = mapped_column(String(512), nullable=True)
    # Opaque encrypted blob (client-side Fernet ciphertext of annotation JSON)
    encrypted_blob: Mapped[str] = mapped_column(Text, nullable=False)
    # Optional device identifier for conflict debugging
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    # Version counter incremented on each push
    version: Mapped[int] = mapped_column(default=1)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
