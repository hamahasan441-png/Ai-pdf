"""Pydantic schemas for chat history endpoints (Part 7.3)."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class CreateSessionRequest(BaseModel):
    title: str = Field(default="Untitled chat", max_length=300)
    document_id: Optional[str] = Field(default=None, max_length=200)


class AppendMessageRequest(BaseModel):
    role: str = Field(..., pattern="^(user|assistant|system)$")
    content: str = Field(..., max_length=50000)


class MessageResponse(BaseModel):
    id: str
    role: str
    content: str
    created_at: datetime


class SessionResponse(BaseModel):
    id: str
    title: str
    document_id: Optional[str] = None
    message_count: int
    created_at: datetime
    updated_at: datetime


class SessionDetailResponse(BaseModel):
    id: str
    title: str
    document_id: Optional[str] = None
    messages: list[MessageResponse]
    created_at: datetime
    updated_at: datetime
