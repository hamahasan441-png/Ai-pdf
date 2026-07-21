"""Extract key dates and deadlines from a document.

Identifies all important dates, deadlines, due dates, expiry dates, and
time-sensitive information — useful for calendar integration and deadline tracking.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
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

router = APIRouter(prefix="/document-ai", tags=["Document AI"])


class ExtractDatesRequest(BaseModel):
    document_text: str = Field(..., max_length=30000)


class DateItem(BaseModel):
    date: str
    description: str
    type: str = ""  # deadline | due_date | start_date | expiry | event | other
    page: int = 0
    urgent: bool = False


class ExtractDatesResponse(BaseModel):
    dates: list[DateItem]
    remaining: int = -1


@router.post("/extract-dates", response_model=ExtractDatesResponse)
async def extract_dates(
    req: ExtractDatesRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Extract all important dates and deadlines from a document."""
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    pro = await is_pro(db, request.headers.get("X-Entitlement-Token"))
    remaining = UNLIMITED
    if not pro:
        identity = identity_for(user, request)
        allowed, count = check_and_increment(identity)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, settings.AI_FREE_DAILY_LIMIT - count)

    messages = [
        {
            "role": "system",
            "content": (
                "Extract ALL dates, deadlines, and time-sensitive information from "
                "this document. For each date return:\n"
                '{"date": "the date string", "description": "what this date is for", '
                '"type": "deadline|due_date|start_date|expiry|event|other", '
                '"urgent": true/false (if within 30 days or explicitly marked urgent)}.\n'
                'Respond with valid JSON: {"dates": [...]}'
            ),
        },
        {"role": "user", "content": f"Document:\n{req.document_text[:10000]}"},
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages, use_advanced=False, max_tokens=2048
    )
    dates = result.get("dates", []) if isinstance(result, dict) else []
    return ExtractDatesResponse(dates=dates, remaining=remaining)
