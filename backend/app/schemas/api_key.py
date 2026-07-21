"""Pydantic schemas for API key endpoints (Part 7.1)."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ApiKeyCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200, description="Human label for the key")
    team_id: Optional[str] = Field(default=None, description="Optional team to associate with")


class ApiKeyCreateResponse(BaseModel):
    """Returned ONCE at creation — includes the full plaintext key."""
    id: str
    name: str
    key: str  # Full plaintext — shown only once, never again
    key_prefix: str
    created_at: datetime


class ApiKeyResponse(BaseModel):
    """List view — never includes the full key."""
    id: str
    name: str
    key_prefix: str
    team_id: Optional[str] = None
    created_at: datetime
    last_used_at: Optional[datetime] = None
    revoked_at: Optional[datetime] = None
    is_active: bool
