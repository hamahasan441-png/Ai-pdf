"""Suggest-edits endpoint — review-first AI editing (Part 4.8).

The product rule is that AI **never silently rewrites** a user's document. The
existing ``/document-ai/rewrite`` returns a whole rewritten blob, which forces a
take-it-or-leave-it choice. This endpoint is different: it returns a list of
**discrete, reviewable suggestions** — each one names the exact original span,
the proposed replacement, a short reason, and a category — so the client can
present them as accept/reject cards and apply only the ones the user approves.

It is purely advisory: the server applies nothing and stores nothing. Metering
and the Pro bypass are identical to the other Document AI endpoints.
"""

import logging
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

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/document-ai", tags=["Document AI"])

# Categories the model is asked to use; anything else is normalised to "other".
_CATEGORIES = {"grammar", "spelling", "clarity", "conciseness", "tone", "other"}

# Hard cap so a runaway model response can't return thousands of edits.
_MAX_EDITS = 100


class SuggestEditsRequest(BaseModel):
    text: str = Field(..., max_length=20000, description="Text to review (not modified)")
    focus: str = Field(
        "all",
        description="What to focus on: grammar | spelling | clarity | conciseness | tone | all",
    )
    language: str = Field("auto", description="Language hint, or 'auto' to detect")


class SuggestedEdit(BaseModel):
    original: str = Field(..., description="Exact span from the input to replace")
    suggestion: str = Field(..., description="Proposed replacement for that span")
    reason: str = Field("", description="Short human-readable rationale")
    category: str = Field("other", description="grammar|spelling|clarity|conciseness|tone|other")


class SuggestEditsResponse(BaseModel):
    edits: list[SuggestedEdit]
    count: int
    remaining: int = -1  # -1 = unlimited (Pro)


@router.post("/suggest-edits", response_model=SuggestEditsResponse)
async def suggest_edits(
    req: SuggestEditsRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Return reviewable edit suggestions for a piece of text. Applies nothing."""
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI service not configured. Set AI_API_KEY.")

    # Meter before spending an AI request (Pro bypasses the cap).
    pro = await is_pro(db, request.headers.get("X-Entitlement-Token"))
    remaining = UNLIMITED
    if not pro:
        identity = identity_for(user, request)
        allowed, count = check_and_increment(identity)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily free AI limit reached.")
        remaining = max(0, settings.AI_FREE_DAILY_LIMIT - count)

    focus = req.focus.strip().lower()
    focus_hint = (
        "grammar, spelling, clarity, conciseness, and tone"
        if focus not in _CATEGORIES or focus == "all"
        else focus
    )
    lang_hint = f" The text is in {req.language}." if req.language != "auto" else ""

    messages = [
        {
            "role": "system",
            "content": (
                "You are a meticulous copy editor. Review the user's text and propose "
                f"specific improvements focused on {focus_hint}.{lang_hint} Do NOT rewrite "
                "the whole text. Instead return a JSON object with an 'edits' array, where "
                "each element has EXACTLY these keys:\n"
                '  "original": the exact substring from the input to change,\n'
                '  "suggestion": the replacement text,\n'
                '  "reason": a short (<= 12 words) explanation,\n'
                '  "category": one of grammar|spelling|clarity|conciseness|tone.\n'
                "Only include genuine improvements; never change meaning, numbers, names, "
                "or facts. If the text is already good, return an empty edits array. "
                "Respond with valid JSON only."
            ),
        },
        {"role": "user", "content": req.text},
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages,
        use_advanced=True,
        max_tokens=4096,
    )

    edits = _parse_edits(result)
    return SuggestEditsResponse(edits=edits, count=len(edits), remaining=remaining)


def _parse_edits(result: object) -> list[SuggestedEdit]:
    """Turn a loosely-typed model response into validated SuggestedEdit items.

    Tolerant of the two shapes models return — ``{"edits": [...]}`` or a bare
    ``[...]`` array — and of extra/missing keys. Any element that lacks a usable
    original/suggestion pair is skipped rather than failing the whole request.
    """
    if isinstance(result, dict):
        raw = result.get("edits", result.get("suggestions", []))
    elif isinstance(result, list):
        raw = result
    else:
        raw = []
    if not isinstance(raw, list):
        return []

    edits: list[SuggestedEdit] = []
    for item in raw[:_MAX_EDITS]:
        if not isinstance(item, dict):
            continue
        original = str(item.get("original", item.get("from", ""))).strip()
        suggestion = str(item.get("suggestion", item.get("to", item.get("replacement", "")))).strip()
        # A suggestion must reference real source text and actually change it.
        if not original or not suggestion or original == suggestion:
            continue
        category = str(item.get("category", "other")).strip().lower()
        if category not in _CATEGORIES:
            category = "other"
        edits.append(
            SuggestedEdit(
                original=original,
                suggestion=suggestion,
                reason=str(item.get("reason", "")).strip()[:200],
                category=category,
            )
        )
    return edits
