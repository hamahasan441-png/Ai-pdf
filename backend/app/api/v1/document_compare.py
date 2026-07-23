"""Document comparison endpoint — compare two documents and highlight differences.

Used when a user uploads two versions of a contract/document and wants to know
what changed. The AI identifies structural and content differences, additions,
and removals — cited by section/page.
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
    check_and_increment_tiered,
    identity_for,
)
from app.services.billing.quota_tiers import get_quota

router = APIRouter(prefix="/document-ai", tags=["Document AI"])


class CompareRequest(BaseModel):
    document_a: str = Field(..., max_length=30000, description="Text of the first document (original)")
    document_b: str = Field(..., max_length=30000, description="Text of the second document (revised)")
    focus: str = Field("all", description="Focus area: all | legal | financial | structural")


class CompareResponse(BaseModel):
    summary: str
    changes: list[dict]  # [{type: added|removed|modified, section, description}]
    remaining: int = -1


@router.post("/compare", response_model=CompareResponse)
async def compare_documents(
    req: CompareRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Compare two document versions and identify differences."""
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    # Meter
    token = request.headers.get("X-Entitlement-Token")
    _tier, limit = await get_quota(db, token)
    remaining = UNLIMITED
    if limit is not None:
        identity = identity_for(user, request)
        allowed, count = check_and_increment_tiered(identity, limit)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, limit - count)

    focus_hint = f" Focus especially on {req.focus} aspects." if req.focus != "all" else ""

    messages = [
        {
            "role": "system",
            "content": (
                "You compare two versions of a document. Identify ALL differences: "
                "additions, removals, and modifications. For each change, note the "
                "section/location and describe what changed.{focus}"
                "\n\nRespond with valid JSON: "
                '{"summary": "...", "changes": [{"type": "added|removed|modified", '
                '"section": "...", "description": "..."}]}'
            ).replace("{focus}", focus_hint),
        },
        {
            "role": "user",
            "content": (
                f"DOCUMENT A (original):\n{req.document_a[:12000]}\n\n"
                f"DOCUMENT B (revised):\n{req.document_b[:12000]}"
            ),
        },
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages,
        use_advanced=True,
        max_tokens=4096,
    )
    return CompareResponse(
        summary=result.get("summary", ""),
        changes=result.get("changes", []),
        remaining=remaining,
    )
