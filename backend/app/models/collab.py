"""Collaboration command log — E8.3 full replay persistence (Phase 5).

Stores serialized editor commands for replay when new client joins.
Server is still relay-only for privacy, but optional persistence allows new clients
to catch up without full document resync.

Design:
- Each record is a command JSON from domain/history/editor_command.dart
- Scoped to team_id + file_hash
- Ordered by timestamp
- Soft-delete not needed, but we keep created_at for ordering and limit 1000 per file_hash
- For multi-instance, replace in-memory manager with Redis pub/sub + this table as log

Privacy: commands contain annotation id + position, not document bytes. Still client-side
can encrypt payload if needed, but for V1 we store plaintext commands (already in team context).
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import DateTime, ForeignKey, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.database import Base


class CollabCommandLog(Base):
    """Persistent log of editor commands for team collab replay."""

    __tablename__ = "collab_command_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    team_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("teams.id", ondelete="CASCADE"), index=True
    )
    file_hash: Mapped[str] = mapped_column(String(128), index=True, nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    device_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    command_type: Mapped[str] = mapped_column(String(64), nullable=False)
    command_json: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), index=True
    )
