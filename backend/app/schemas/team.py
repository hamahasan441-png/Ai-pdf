"""Pydantic schemas for team / enterprise endpoints (Part 5.8 + E8.1 per-team quota + E8.2 SSO)."""

from datetime import datetime
from typing import Optional

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
    ai_daily_quota: Optional[int] = None
    sso_required: bool = False
    created_at: datetime


class TeamQuotaUpdateRequest(BaseModel):
    ai_daily_quota: Optional[int] = Field(
        default=None, description="Daily AI quota for whole team (None = unlimited / use user tier). 0 is invalid, must be >=1."
    )
    sso_required: Optional[bool] = None

    def validate_quota(self) -> None:
        if self.ai_daily_quota is not None and self.ai_daily_quota < 1:
            raise ValueError("ai_daily_quota must be >=1 or None")


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
    ai_daily_quota: Optional[int] = None
    sso_required: bool = False
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
