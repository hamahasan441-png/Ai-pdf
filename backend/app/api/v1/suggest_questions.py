"""Suggest questions endpoint — AI-generated questions about a document.

After the user opens a document, the app can call this endpoint to get a list
of smart, relevant questions the user might want to ask. These populate the
"Suggested questions" section in the AI chat UI — making the AI assistant
feel proactive and intelligent from the first interaction.
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


class SuggestQuestionsRequest(BaseModel):
    document_text: str = Field(..., max_length=30000,
                               description="First ~30K chars of the document")
    document_type: str = Field("unknown", description="Optional: invoice, contract, form, letter")
    count: int = Field(5, ge=1, le=10, description="Number of questions to suggest")


class SuggestQuestionsResponse(BaseModel):
    questions: list[str]
    remaining: int = -1


@router.post("/suggest-questions", response_model=SuggestQuestionsResponse)
async def suggest_questions(
    req: SuggestQuestionsRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate smart, relevant questions about a document."""
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    # Meter
    pro = await is_pro(db, request.headers.get("X-Entitlement-Token"))
    remaining = UNLIMITED
    if not pro:
        identity = identity_for(user, request)
        allowed, count = check_and_increment(identity)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, settings.AI_FREE_DAILY_LIMIT - count)

    type_hint = f" This is a {req.document_type}." if req.document_type != "unknown" else ""

    messages = [
        {
            "role": "system",
            "content": (
                f"Generate exactly {req.count} smart, specific questions a user would "
                "want to ask about this document. Questions should be diverse: mix "
                "factual (dates, amounts, names), analytical (implications, risks), "
                "and action-oriented (what to do next, deadlines).{type_hint}"
                "\n\nRespond with a JSON array of strings only: [\"q1\", \"q2\", ...]"
            ).replace("{type_hint}", type_hint),
        },
        {"role": "user", "content": f"Document:\n{req.document_text[:8000]}"},
    ]

    import json
    reply = await ai_provider.chat_completion(
        messages=messages, temperature=0.4, max_tokens=1024
    )
    # Parse the JSON array
    try:
        questions = json.loads(reply)
        if not isinstance(questions, list):
            questions = [reply]
    except json.JSONDecodeError:
        # Fallback: split by newlines
        questions = [q.strip().lstrip('0123456789.-) ') for q in reply.split('\n') if q.strip()]

    return SuggestQuestionsResponse(
        questions=questions[:req.count],
        remaining=remaining,
    )
