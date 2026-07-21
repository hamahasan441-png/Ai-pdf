"""Pydantic schemas for webhook endpoints (Part 7.2)."""

from datetime import datetime

from pydantic import BaseModel, Field, HttpUrl


class WebhookCreateRequest(BaseModel):
    url: HttpUrl = Field(..., description="HTTPS URL to receive POST deliveries")
    events: list[str] = Field(
        ...,
        min_length=1,
        description="Event types to subscribe to (e.g. 'ai.chat.complete')",
    )


class WebhookCreateResponse(BaseModel):
    """Returned at creation — includes the secret (shown once)."""
    id: str
    url: str
    events: list[str]
    secret: str  # Shown only once
    active: bool
    created_at: datetime


class WebhookResponse(BaseModel):
    """List view — never includes the secret."""
    id: str
    url: str
    events: list[str]
    active: bool
    created_at: datetime


class WebhookEventTypesResponse(BaseModel):
    """Available event types the user can subscribe to."""
    event_types: list[str]
