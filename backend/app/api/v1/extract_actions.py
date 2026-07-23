"""Extract action items / todos from a document.

Identifies tasks, obligations, requirements, and next steps — useful for
task management integration and ensuring nothing is missed in a complex document.
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


class ExtractActionsRequest(BaseModel):
    document_text: str = Field(..., max_length=30000)


class ActionItem(BaseModel):
    action: str
    assignee: str = ""  # who is responsible (if mentioned)
    deadline: str = ""  # deadline if mentioned
    priority: str = "normal"  # high | normal | low
    section: str = ""  # which part of the document


class ExtractActionsResponse(BaseModel):
    actions: list[ActionItem]
    remaining: int = -1


@router.post("/extract-actions", response_model=ExtractActionsResponse)
async def extract_actions(
    req: ExtractActionsRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Extract action items, obligations, and next steps from a document."""
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    token = request.headers.get("X-Entitlement-Token")
    _tier, limit = await get_quota(db, token)
    remaining = UNLIMITED
    if limit is not None:
        identity = identity_for(user, request)
        allowed, count = check_and_increment_tiered(identity, limit)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, limit - count)

    messages = [
        {
            "role": "system",
            "content": (
                "Extract ALL action items, tasks, obligations, requirements, and "
                "next steps from this document. For each item return:\n"
                '{"action": "what needs to be done", "assignee": "who (if stated)", '
                '"deadline": "when (if stated)", "priority": "high|normal|low", '
                '"section": "which part of the document"}.\n'
                'Mark as high priority if: explicitly urgent, has a close deadline, '
                'or involves legal/financial consequences.\n'
                'Respond with valid JSON: {"actions": [...]}'
            ),
        },
        {"role": "user", "content": f"Document:\n{req.document_text[:10000]}"},
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages, use_advanced=False, max_tokens=2048
    )
    actions = result.get("actions", []) if isinstance(result, dict) else []
    return ExtractActionsResponse(actions=actions, remaining=remaining)
