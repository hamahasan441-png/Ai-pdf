"""Access-control and audit helpers for team endpoints (Part 5.8).

Centralises the "is this user allowed to touch this team?" logic so every route
enforces the same rules, and provides a single place to append audit entries.
"""

import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import AuthorizationError, NotFoundError
from app.models.team import Team, TeamAuditLog, TeamMember, TeamRole


async def get_team(db: AsyncSession, team_id: uuid.UUID) -> Optional[Team]:
    """Fetch a team by id, or None."""
    return (
        await db.execute(select(Team).where(Team.id == team_id))
    ).scalar_one_or_none()


async def get_membership(
    db: AsyncSession, team_id: uuid.UUID, user_id: uuid.UUID
) -> Optional[TeamMember]:
    """Return the user's membership row for a team, or None if not a member."""
    return (
        await db.execute(
            select(TeamMember).where(
                TeamMember.team_id == team_id,
                TeamMember.user_id == user_id,
            )
        )
    ).scalar_one_or_none()


async def require_member(
    db: AsyncSession, team_id: uuid.UUID, user_id: uuid.UUID
) -> TeamMember:
    """Ensure the team exists and the user is a member; return the membership.

    Raises 404 if the team does not exist (also used to avoid leaking team
    existence to non-members — a non-member gets 404, not 403, on lookup).
    """
    team = await get_team(db, team_id)
    if team is None:
        raise NotFoundError("Team")
    membership = await get_membership(db, team_id, user_id)
    if membership is None:
        raise NotFoundError("Team")
    return membership


async def require_manager(
    db: AsyncSession, team_id: uuid.UUID, user_id: uuid.UUID
) -> TeamMember:
    """Ensure the user is an owner/admin of the team; return the membership."""
    membership = await require_member(db, team_id, user_id)
    if membership.role not in TeamRole.MANAGERS:
        raise AuthorizationError("Requires team owner or admin role")
    return membership


async def member_count(db: AsyncSession, team_id: uuid.UUID) -> int:
    """Number of members in a team."""
    rows = (
        await db.execute(select(TeamMember.id).where(TeamMember.team_id == team_id))
    ).all()
    return len(rows)


async def record_audit(
    db: AsyncSession,
    *,
    team_id: uuid.UUID,
    actor_id: uuid.UUID,
    action: str,
    target: Optional[str] = None,
    detail: Optional[str] = None,
) -> None:
    """Append a team audit entry. Flushed with the surrounding transaction."""
    db.add(
        TeamAuditLog(
            team_id=team_id,
            actor_id=actor_id,
            action=action,
            target=target,
            detail=detail,
        )
    )
    await db.flush()
