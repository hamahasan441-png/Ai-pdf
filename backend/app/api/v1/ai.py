"""Managed AI proxy — lets the app offer AI without the user supplying a key.

The server holds the provider key and meters free usage per identity (user id
if logged in, else client IP). This is the growth engine: mainstream users get
working AI out of the box, and the free daily cap creates a natural upgrade
path to Pro (unlimited).

Metering is centralised in ``app.services.ai.usage_limiter`` so this endpoint
and the Document AI endpoints share one cap and one Pro-bypass rule.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.provider import ai_provider
from app.services.ai.usage_limiter import (
    UNLIMITED,
    check_and_increment,
    identity_for,
    is_pro,
)

router = APIRouter()


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    messages: list[ChatMessage]
    use_advanced: bool = False
    temperature: float = 0.3


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
    """Managed chat completion. Unlimited for verified Pro; else metered."""
    if not settings.AI_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Managed AI is not configured on the server.",
        )
    if not req.messages:
        raise HTTPException(status_code=422, detail="messages must not be empty")

    # Verified Pro (via purchase token) bypasses the free daily limit.
    pro = await is_pro(db, request.headers.get("X-Entitlement-Token"))
    remaining = UNLIMITED
    if not pro:
        identity = identity_for(user, request)
        allowed, count = check_and_increment(identity)
        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Daily free AI limit reached. Upgrade to Pro for unlimited AI.",
            )
        remaining = max(0, settings.AI_FREE_DAILY_LIMIT - count)

    reply = await ai_provider.chat_completion(
        messages=[m.model_dump() for m in req.messages],
        temperature=req.temperature,
        use_advanced=req.use_advanced,
    )
    return ChatResponse(reply=reply, remaining=remaining)
