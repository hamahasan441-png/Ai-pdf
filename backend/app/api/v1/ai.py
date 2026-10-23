"""Managed AI proxy — lets the app offer AI without the user supplying a key.

The server holds the provider key and meters free usage per identity (user id
if logged in, else client IP). This is the growth engine: mainstream users get
working AI out of the box, and the free daily cap creates a natural upgrade
path to Pro (unlimited).

Metering uses per-plan quota tiers (free / basic / Pro) resolved from the
``X-Entitlement-Token`` header. ``app.services.billing.quota_tiers`` and
``app.services.ai.usage_limiter`` share one cap and one tier-bypass rule
with the Document AI endpoints.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.provider import ai_provider
from app.services.ai.usage_limiter import (
    UNLIMITED,
    check_and_increment_tiered,
    identity_for,
)
from app.services.billing.quota_tiers import PAID_TIERS, get_quota

router = APIRouter()


# Request size limits: bound provider cost / memory per call.
MAX_MESSAGES = 50
MAX_MESSAGE_CHARS = 50_000
MAX_TOTAL_CHARS = 100_000
TEMPERATURE_MIN = 0.0
TEMPERATURE_MAX = 1.5


class ChatMessage(BaseModel):
    role: str = Field(..., max_length=32)
    content: str = Field(..., max_length=MAX_MESSAGE_CHARS)


class ChatRequest(BaseModel):
    messages: list[ChatMessage] = Field(..., max_length=MAX_MESSAGES)
    # Honoured only for paid tiers; free callers silently get the default model.
    use_advanced: bool = False
    temperature: float = Field(0.3, allow_inf_nan=False)

    @field_validator("temperature")
    @classmethod
    def _clamp_temperature(cls, v: float) -> float:
        return min(max(v, TEMPERATURE_MIN), TEMPERATURE_MAX)

    @model_validator(mode="after")
    def _total_size(self) -> "ChatRequest":
        if sum(len(m.content) for m in self.messages) > MAX_TOTAL_CHARS:
            raise ValueError(f"messages exceed {MAX_TOTAL_CHARS} characters in total")
        return self


class ChatResponse(BaseModel):
    reply: str
    remaining: int


@router.post("/chat", response_model=ChatResponse)
async def managed_chat(
    req: ChatRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Managed chat completion — tier-aware metering.

    - Pro (monthly/yearly/lifetime) → unlimited.
    - Basic → ``AI_BASIC_DAILY_LIMIT`` per day.
    - Free (no/invalid token) → ``AI_FREE_DAILY_LIMIT`` per day.
    """
    if not settings.AI_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Managed AI is not configured on the server.",
        )
    if not req.messages:
        raise HTTPException(status_code=422, detail="messages must not be empty")

    token = request.headers.get("X-Entitlement-Token")
    tier, limit = await get_quota(db, token)
    remaining = UNLIMITED
    if limit is not None:
        identity = identity_for(user, request)
        allowed, count = check_and_increment_tiered(identity, limit)
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Daily AI limit reached. Upgrade to Pro for unlimited AI.",
            )
        remaining = max(0, limit - count)

    reply = await ai_provider.chat_completion(
        messages=[m.model_dump() for m in req.messages],
        temperature=req.temperature,
        use_advanced=req.use_advanced and tier in PAID_TIERS,
    )
    return ChatResponse(reply=reply, remaining=remaining)
