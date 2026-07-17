"""Managed AI proxy — lets the app offer AI without the user supplying a key.

The server holds the provider key and meters free usage per identity (user id
if logged in, else client IP). This is the growth engine: mainstream users get
working AI out of the box, and the free daily cap creates a natural upgrade
path to Pro (unlimited).

NOTE: the in-memory limiter below is per-process and resets on restart — fine
for a single instance / early stage. For multi-instance production, back it
with Redis (already a dependency) keyed the same way, and bypass the cap for
verified-Pro users once entitlements are persisted.
"""

from datetime import date
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.models.user import User
from app.services.ai.provider import ai_provider

router = APIRouter()

# identity -> (yyyy-mm-dd, count). Swap for Redis in production.
_usage: dict[str, tuple[str, int]] = {}


def _check_and_increment(key: str) -> tuple[bool, int]:
    today = date.today().isoformat()
    day, count = _usage.get(key, (today, 0))
    if day != today:
        day, count = today, 0
    if count >= settings.AI_FREE_DAILY_LIMIT:
        return False, count
    _usage[key] = (today, count + 1)
    return True, count + 1


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
):
    """Managed chat completion. Metered by the free daily limit."""
    if not settings.AI_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Managed AI is not configured on the server.",
        )
    if not req.messages:
        raise HTTPException(status_code=422, detail="messages must not be empty")

    identity = str(user.id) if user else (request.client.host if request.client else "anon")
    allowed, count = _check_and_increment(identity)
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily free AI limit reached. Upgrade to Pro for unlimited AI.",
        )

    reply = await ai_provider.chat_completion(
        messages=[m.model_dump() for m in req.messages],
        temperature=req.temperature,
        use_advanced=req.use_advanced,
    )
    return ChatResponse(
        reply=reply,
        remaining=max(0, settings.AI_FREE_DAILY_LIMIT - count),
    )
