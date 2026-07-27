"""Team / enterprise models (Part 5.8).

Enterprise usage is modelled as **teams** with **members** (each carrying a
role) and **shared templates** (reusable form/document templates owned by a team
rather than an individual).

These are additive: they introduce new tables with foreign keys onto
``users.id`` but do NOT modify the existing ``User`` model or its relationships,
so nothing that depends on ``User`` changes behaviour.
"""

import uuid
from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Uuid,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.database import Base


class TeamRole(str):
    """Allowed membership roles (kept as plain strings for portability).

    ``owner``  — created the team; full control, cannot be removed.
    ``admin``  — can manage members and templates.
    ``member`` — can use shared templates and create new ones.
    """

    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"

    #: Roles allowed to manage members / export the audit log.
    MANAGERS = frozenset({OWNER, ADMIN})
    #: All valid role values (for validation).
    ALL = frozenset({OWNER, ADMIN, MEMBER})


class Team(Base):
    """A group of users who share templates and (later) quotas/billing.

    E8.1 — Per-team AI quota: optional daily limit that overrides the per-user
    tier when acting in team context (X-Team-Id header). None = use user tier.
    """

    __tablename__ = "teams"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    # E8.1 — Daily AI quota for the whole team pool (None = unlimited or use user tier, depending on enforcement).
    ai_daily_quota: Mapped[int | None] = mapped_column(Integer, nullable=True, default=None)
    # E8.2 — Optional SSO requirement flag (enterprise)
    sso_required: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    members: Mapped[list["TeamMember"]] = relationship(
        back_populates="team", cascade="all, delete-orphan"
    )
    templates: Mapped[list["SharedTemplate"]] = relationship(
        back_populates="team", cascade="all, delete-orphan"
    )


class TeamMember(Base):
    """Membership of a :class:`User` in a :class:`Team` with a role."""

    __tablename__ = "team_members"
    __table_args__ = (
        UniqueConstraint("team_id", "user_id", name="uq_team_member"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    team_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("teams.id", ondelete="CASCADE"), index=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    role: Mapped[str] = mapped_column(String(16), default=TeamRole.MEMBER, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )

    team: Mapped["Team"] = relationship(back_populates="members")


class TeamAuditLog(Base):
    """Append-only record of security-relevant team actions (Part 5.8).

    Unlike the process-level :mod:`app.middleware.audit_log` (which streams to
    the app log), this table persists team-scoped events so an admin can export
    a compliance trail: who added/removed members, created/deleted templates, etc.
    """

    __tablename__ = "team_audit_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    team_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("teams.id", ondelete="CASCADE"), index=True
    )
    actor_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    target: Mapped[str | None] = mapped_column(String(255), nullable=True)
    detail: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )


class SharedTemplate(Base):
    """A reusable template owned by a team (e.g. a saved form layout).

    ``content`` is opaque JSON serialised as text so the same table works on
    Postgres and the SQLite test DB without a JSON column type dependency.
    """

    __tablename__ = "shared_templates"

    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    team_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("teams.id", ondelete="CASCADE"), index=True
    )
    created_by: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    content: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc)
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )

    team: Mapped["Team"] = relationship(back_populates="templates")
