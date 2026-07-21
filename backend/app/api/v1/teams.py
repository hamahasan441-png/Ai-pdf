"""Team / enterprise endpoints (Part 5.8).

Teams let organisations share templates and manage members with roles. Every
route is authenticated; mutating routes enforce role checks via
``app.services.team.team_service``. Member add/remove and template delete are
recorded to a per-team audit log that owners/admins can export.
"""

import json
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.core.exceptions import AuthorizationError, NotFoundError, ValidationError
from app.db.database import get_db
from app.models.team import (
    SharedTemplate,
    Team,
    TeamAuditLog,
    TeamMember,
    TeamRole,
)
from app.models.user import User
from app.schemas.team import (
    AuditEntry,
    AuditExportResponse,
    MemberAddRequest,
    MemberResponse,
    TeamCreateRequest,
    TeamDetailResponse,
    TeamResponse,
    TemplateCreateRequest,
    TemplateResponse,
)
from app.services.team import team_service

router = APIRouter()


# --- Teams ---------------------------------------------------------------

@router.post("", response_model=TeamResponse, status_code=201)
async def create_team(
    request: TeamCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a team; the creator becomes its owner."""
    team = Team(name=request.name, owner_id=user.id)
    db.add(team)
    await db.flush()

    db.add(TeamMember(team_id=team.id, user_id=user.id, role=TeamRole.OWNER))
    await db.flush()
    await team_service.record_audit(
        db, team_id=team.id, actor_id=user.id, action="team.create", detail=request.name
    )

    return TeamResponse(
        id=str(team.id),
        name=team.name,
        owner_id=str(team.owner_id),
        role=TeamRole.OWNER,
        member_count=1,
        created_at=team.created_at,
    )


@router.get("", response_model=list[TeamResponse])
async def list_teams(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all teams the authenticated user belongs to."""
    memberships = (
        await db.execute(select(TeamMember).where(TeamMember.user_id == user.id))
    ).scalars().all()

    out: list[TeamResponse] = []
    for m in memberships:
        team = await team_service.get_team(db, m.team_id)
        if team is None:
            continue
        out.append(
            TeamResponse(
                id=str(team.id),
                name=team.name,
                owner_id=str(team.owner_id),
                role=m.role,
                member_count=await team_service.member_count(db, team.id),
                created_at=team.created_at,
            )
        )
    return out


@router.get("/{team_id}", response_model=TeamDetailResponse)
async def get_team_detail(
    team_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Team detail including its members (any member may view)."""
    membership = await team_service.require_member(db, team_id, user.id)
    team = await team_service.get_team(db, team_id)

    members = (
        await db.execute(select(TeamMember).where(TeamMember.team_id == team_id))
    ).scalars().all()

    member_models: list[MemberResponse] = []
    for m in members:
        u = (
            await db.execute(select(User).where(User.id == m.user_id))
        ).scalar_one_or_none()
        if u is None:
            continue
        member_models.append(
            MemberResponse(
                user_id=str(u.id),
                email=u.email,
                full_name=u.full_name,
                role=m.role,
                joined_at=m.created_at,
            )
        )

    return TeamDetailResponse(
        id=str(team.id),
        name=team.name,
        owner_id=str(team.owner_id),
        role=membership.role,
        members=member_models,
        created_at=team.created_at,
    )


# --- Members -------------------------------------------------------------

@router.post("/{team_id}/members", response_model=MemberResponse, status_code=201)
async def add_member(
    team_id: uuid.UUID,
    request: MemberAddRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Add a member by email (owner/admin only). Owner role cannot be assigned."""
    await team_service.require_manager(db, team_id, user.id)

    role = request.role.strip().lower()
    if role not in {TeamRole.ADMIN, TeamRole.MEMBER}:
        raise ValidationError("role must be 'admin' or 'member'")

    target = (
        await db.execute(select(User).where(User.email == request.email))
    ).scalar_one_or_none()
    if target is None:
        raise NotFoundError("User")

    existing = await team_service.get_membership(db, team_id, target.id)
    if existing is not None:
        raise ValidationError("User is already a member of this team")

    member = TeamMember(team_id=team_id, user_id=target.id, role=role)
    db.add(member)
    await db.flush()
    await team_service.record_audit(
        db,
        team_id=team_id,
        actor_id=user.id,
        action="member.add",
        target=str(target.id),
        detail=f"{target.email} as {role}",
    )

    return MemberResponse(
        user_id=str(target.id),
        email=target.email,
        full_name=target.full_name,
        role=role,
        joined_at=member.created_at,
    )


@router.delete("/{team_id}/members/{member_user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    team_id: uuid.UUID,
    member_user_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Remove a member (owner/admin only). The owner cannot be removed."""
    await team_service.require_manager(db, team_id, user.id)

    membership = await team_service.get_membership(db, team_id, member_user_id)
    if membership is None:
        raise NotFoundError("Member")
    if membership.role == TeamRole.OWNER:
        raise AuthorizationError("The team owner cannot be removed")

    await db.delete(membership)
    await team_service.record_audit(
        db,
        team_id=team_id,
        actor_id=user.id,
        action="member.remove",
        target=str(member_user_id),
    )
    return None


# --- Shared templates ----------------------------------------------------

@router.get("/{team_id}/templates", response_model=list[TemplateResponse])
async def list_templates(
    team_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List shared templates for a team (any member)."""
    await team_service.require_member(db, team_id, user.id)
    templates = (
        await db.execute(
            select(SharedTemplate).where(SharedTemplate.team_id == team_id)
        )
    ).scalars().all()
    return [_template_to_response(t) for t in templates]


@router.post("/{team_id}/templates", response_model=TemplateResponse, status_code=201)
async def create_template(
    team_id: uuid.UUID,
    request: TemplateCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a shared template (any member)."""
    await team_service.require_member(db, team_id, user.id)

    template = SharedTemplate(
        team_id=team_id,
        created_by=user.id,
        name=request.name,
        description=request.description,
        content=json.dumps(request.content),
    )
    db.add(template)
    await db.flush()
    await team_service.record_audit(
        db,
        team_id=team_id,
        actor_id=user.id,
        action="template.create",
        target=str(template.id),
        detail=request.name,
    )
    return _template_to_response(template)


@router.delete(
    "/{team_id}/templates/{template_id}", status_code=status.HTTP_204_NO_CONTENT
)
async def delete_template(
    team_id: uuid.UUID,
    template_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a shared template (its creator, or an owner/admin)."""
    membership = await team_service.require_member(db, team_id, user.id)

    template = (
        await db.execute(
            select(SharedTemplate).where(
                SharedTemplate.id == template_id,
                SharedTemplate.team_id == team_id,
            )
        )
    ).scalar_one_or_none()
    if template is None:
        raise NotFoundError("Template")

    is_manager = membership.role in TeamRole.MANAGERS
    if not is_manager and template.created_by != user.id:
        raise AuthorizationError("Only the creator or a team manager can delete this")

    await db.delete(template)
    await team_service.record_audit(
        db,
        team_id=team_id,
        actor_id=user.id,
        action="template.delete",
        target=str(template_id),
    )
    return None


# --- Audit export --------------------------------------------------------

@router.get("/{team_id}/audit", response_model=AuditExportResponse)
async def export_audit(
    team_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Export the team's audit trail (owner/admin only)."""
    await team_service.require_manager(db, team_id, user.id)

    logs = (
        await db.execute(
            select(TeamAuditLog)
            .where(TeamAuditLog.team_id == team_id)
            .order_by(TeamAuditLog.created_at.desc())
        )
    ).scalars().all()

    entries = [
        AuditEntry(
            timestamp=log.created_at,
            action=log.action,
            actor_id=str(log.actor_id) if log.actor_id else "",
            target=log.target,
            detail=log.detail,
        )
        for log in logs
    ]
    return AuditExportResponse(
        team_id=str(team_id),
        generated_at=datetime.now(timezone.utc),
        count=len(entries),
        entries=entries,
    )


# --- helpers -------------------------------------------------------------

def _template_to_response(t: SharedTemplate) -> TemplateResponse:
    try:
        content = json.loads(t.content) if t.content else {}
    except (ValueError, TypeError):
        content = {}
    return TemplateResponse(
        id=str(t.id),
        team_id=str(t.team_id),
        created_by=str(t.created_by) if t.created_by else None,
        name=t.name,
        description=t.description,
        content=content,
        created_at=t.created_at,
        updated_at=t.updated_at,
    )
