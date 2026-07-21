"""Pydantic schemas for team / enterprise endpoints (Part 5.8)."""

from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


# --- Teams ---------------------------------------------------------------

class TeamCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)


class TeamResponse(BaseModel):
    id: str
    name: str
    owner_id: str
    role: str  # the requesting user's role in this team
    member_count: int
    created_at: datetime


# --- Members -------------------------------------------------------------

class MemberAddRequest(BaseModel):
    email: EmailStr
    role: str = "member"  # "admin" | "member" (owner is assigned only on create)


class MemberResponse(BaseModel):
    user_id: str
    email: str
    full_name: str
    role: str
    joined_at: datetime


class TeamDetailResponse(BaseModel):
    id: str
    name: str
    owner_id: str
    role: str
    members: list[MemberResponse]
    created_at: datetime


# --- Shared templates ----------------------------------------------------

class TemplateCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    content: dict = Field(default_factory=dict)


class TemplateResponse(BaseModel):
    id: str
    team_id: str
    created_by: str | None
    name: str
    description: str | None
    content: dict
    created_at: datetime
    updated_at: datetime


# --- Audit ---------------------------------------------------------------

class AuditEntry(BaseModel):
    timestamp: datetime
    action: str
    actor_id: str
    target: str | None = None
    detail: str | None = None


class AuditExportResponse(BaseModel):
    team_id: str
    generated_at: datetime
    count: int
    entries: list[AuditEntry]
