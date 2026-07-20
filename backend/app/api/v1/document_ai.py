"""Document AI endpoints — Chat with PDF, Summarize, Translate, Rewrite, Extract.

These endpoints power the app's AI document intelligence features. Every
endpoint is metered exactly like the managed chat endpoint: verified-Pro users
(active purchase token) are unlimited, everyone else shares the same free daily
cap via ``app.services.ai.usage_limiter``.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
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

router = APIRouter(prefix="/document-ai", tags=["document-ai"])


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class DocumentChatRequest(BaseModel):
    """Chat with a document."""
    document_text: str = Field(..., max_length=50000,
                               description="OCR/extracted text of the document (from client)")
    question: str = Field(..., max_length=2000)
    context_pages: list[str] = Field(default_factory=list,
                                     description="Pre-retrieved relevant page excerpts")
    history: list[dict] = Field(default_factory=list,
                                description="Previous messages [{role, content}]")


class DocumentChatResponse(BaseModel):
    answer: str
    cited_pages: list[int] = []
    remaining: int = -1  # -1 = unlimited (Pro)


class SummarizeRequest(BaseModel):
    document_text: str = Field(..., max_length=50000)
    language: str = "auto"
    style: str = "structured"  # structured | brief | bullet


class SummarizeResponse(BaseModel):
    summary: str
    document_type: str = "unknown"
    key_entities: dict = {}
    remaining: int = -1


class TranslateRequest(BaseModel):
    text: str = Field(..., max_length=10000)
    target_language: str = Field(..., description="e.g. 'Arabic', 'German', 'Kurdish (Sorani)'")
    source_language: str = "auto"


class TranslateResponse(BaseModel):
    translated_text: str
    detected_source: str = ""
    remaining: int = -1


class RewriteRequest(BaseModel):
    text: str = Field(..., max_length=10000)
    style: str = "professional"  # professional | casual | formal | simplified


class RewriteResponse(BaseModel):
    rewritten_text: str
    changes_summary: str = ""
    remaining: int = -1


class ExtractDataRequest(BaseModel):
    document_text: str = Field(..., max_length=50000)
    schema_hint: str = ""  # Optional: tell AI what to extract


class ExtractDataResponse(BaseModel):
    data: dict
    remaining: int = -1


class AnalyzeRequest(BaseModel):
    document_text: str = Field(..., max_length=50000)
    language: str = "auto"


class AnalyzeResponse(BaseModel):
    """One structured 'understand this document' result.

    Powers an Insights panel and seeds the chat's suggested questions. Distinct
    from summarize/extract: it returns the full structured view in one call.
    """
    analysis: dict
    remaining: int = -1


class FormFieldHint(BaseModel):
    """A form field the on-device detector was unsure about."""
    label: str = Field(..., max_length=300)
    context: str = Field("", max_length=600,
                         description="Nearby text / visible options, if any")


class UnderstandFormRequest(BaseModel):
    """Semantic classification of uncertain form fields.

    The client runs fast on-device heuristics first; only the low-confidence
    field labels are sent here (never the document), so this stays cheap and
    private. profile_keys lets the model suggest which saved profile value maps
    to each field.
    """
    fields: list[FormFieldHint] = Field(..., max_length=200)
    profile_keys: list[str] = Field(default_factory=list)
    language: str = "auto"


class UnderstandFormResponse(BaseModel):
    # Each item: {label, field_type, profile_key, validation, confidence}
    fields: list[dict]
    remaining: int = -1


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@router.post("/chat", response_model=DocumentChatResponse)
async def chat_with_document(
    req: DocumentChatRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Chat with a document — ask any question, get an answer grounded in the text."""
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    # Build grounded prompt
    context = "\n---\n".join(req.context_pages) if req.context_pages else req.document_text[:8000]

    messages = [
        {
            "role": "system",
            "content": (
                "You are a helpful document assistant. Answer the user's question "
                "based ONLY on the provided document context. Cite page numbers if available. "
                "If the answer is not in the context, say so clearly.\n\n"
                f"Document context:\n{context}"
            ),
        },
    ]

    # Add conversation history
    for msg in req.history[-10:]:  # Keep last 10 messages for context window
        messages.append({"role": msg["role"], "content": msg["content"]})

    messages.append({"role": "user", "content": req.question})

    reply = await ai_provider.chat_completion(
        messages=messages,
        temperature=0.2,
        max_tokens=2048,
    )
    return DocumentChatResponse(answer=reply, cited_pages=[], remaining=remaining)


@router.post("/summarize", response_model=SummarizeResponse)
async def summarize_document(
    req: SummarizeRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Generate a structured summary of a document."""
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    style_instruction = {
        "structured": "Provide a structured summary: 1) Document type, 2) Key points (bullets), 3) Important entities, 4) Action items.",
        "brief": "Provide a 2-3 sentence summary capturing the essential information.",
        "bullet": "Provide a bullet-point summary with one key fact per bullet.",
    }.get(req.style, "Summarize clearly and concisely.")

    lang_hint = f" Respond in {req.language}." if req.language != "auto" else ""

    messages = [
        {"role": "system", "content": f"You are an expert document summarizer.{lang_hint}"},
        {"role": "user", "content": f"{style_instruction}\n\nDocument:\n{req.document_text[:12000]}"},
    ]

    reply = await ai_provider.chat_completion(
        messages=messages,
        temperature=0.2,
        max_tokens=2048,
    )
    return SummarizeResponse(summary=reply, remaining=remaining)


@router.post("/translate", response_model=TranslateResponse)
async def translate_text(
    req: TranslateRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Translate document text to any language."""
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    source_hint = f" from {req.source_language}" if req.source_language != "auto" else ""

    messages = [
        {
            "role": "system",
            "content": (
                f"You are a professional translator. Translate the following text{source_hint} "
                f"to {req.target_language}. Preserve meaning, tone, and formatting. "
                "Return ONLY the translated text, no commentary."
            ),
        },
        {"role": "user", "content": req.text},
    ]

    reply = await ai_provider.chat_completion(
        messages=messages,
        temperature=0.1,
        max_tokens=4096,
    )
    return TranslateResponse(translated_text=reply, remaining=remaining)


@router.post("/rewrite", response_model=RewriteResponse)
async def rewrite_text(
    req: RewriteRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Rewrite text with improved clarity, grammar, or style."""
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    style_prompt = {
        "professional": "Make it professional and clear.",
        "casual": "Make it conversational and friendly.",
        "formal": "Make it formal and suitable for official documents.",
        "simplified": "Simplify the language for easy understanding (plain language).",
    }.get(req.style, "Improve clarity and grammar.")

    messages = [
        {
            "role": "system",
            "content": f"You are a professional editor. Rewrite the text to: {style_prompt} "
                       "Preserve the original meaning. Return ONLY the rewritten text.",
        },
        {"role": "user", "content": req.text},
    ]

    reply = await ai_provider.chat_completion(
        messages=messages,
        temperature=0.3,
        max_tokens=4096,
    )
    return RewriteResponse(rewritten_text=reply, remaining=remaining)


@router.post("/extract", response_model=ExtractDataResponse)
async def extract_data(
    req: ExtractDataRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Extract structured data from a document as JSON."""
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    hint = f" {req.schema_hint}" if req.schema_hint else ""

    messages = [
        {
            "role": "system",
            "content": (
                "You are a data extraction expert. Extract ALL structured data from "
                "this document as a clean JSON object with meaningful keys. "
                "Include: names, dates, amounts, addresses, reference numbers, "
                f"and any other structured information.{hint}"
                "\n\nRespond with valid JSON only."
            ),
        },
        {"role": "user", "content": f"Extract data from:\n{req.document_text[:12000]}"},
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages,
        use_advanced=True,
        max_tokens=4096,
    )
    return ExtractDataResponse(data=result, remaining=remaining)


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze_document(
    req: AnalyzeRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Structured document intelligence: type, summary, entities, actions,
    and suggested questions — returned as one JSON object for an Insights panel.
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    lang_hint = f" Respond in {req.language}." if req.language != "auto" else ""

    messages = [
        {
            "role": "system",
            "content": (
                "You are a document intelligence engine. Analyze the document and "
                "return a single JSON object with EXACTLY these keys:\n"
                '  "document_type": short label (e.g. invoice, contract, form, letter),\n'
                '  "language": detected language name,\n'
                '  "summary": 2-4 sentence plain summary,\n'
                '  "key_points": array of short strings,\n'
                '  "entities": {"people": [], "organizations": [], "dates": [], '
                '"amounts": [], "ids": []},\n'
                '  "action_items": array of short strings (may be empty),\n'
                '  "suggested_questions": array of 3-5 questions a user might ask.\n'
                f"Base everything ONLY on the document content.{lang_hint} "
                "Respond with valid JSON only."
            ),
        },
        {"role": "user", "content": f"Document:\n{req.document_text[:12000]}"},
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages,
        use_advanced=True,
        max_tokens=4096,
    )
    return AnalyzeResponse(analysis=result, remaining=remaining)


@router.post("/understand-form", response_model=UnderstandFormResponse)
async def understand_form(
    req: UnderstandFormRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Semantic fallback for smart-form field detection.

    Given labels the on-device heuristics couldn't confidently classify (plus the
    available profile keys), return each field's canonical type, the best-matching
    profile key (or empty), a validation kind, and a confidence score.
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    field_lines = "\n".join(
        f"{i}. label={f.label!r} context={f.context!r}"
        for i, f in enumerate(req.fields)
    )
    keys_hint = (
        f"Available profile keys to map to (use exactly one or \"\"): {req.profile_keys}"
        if req.profile_keys
        else 'No profile keys provided; return "" for profile_key.'
    )
    lang_hint = f" Field language: {req.language}." if req.language != "auto" else ""

    messages = [
        {
            "role": "system",
            "content": (
                "You classify form fields. For EACH input field return an object with:\n"
                '  "label": the original label,\n'
                '  "field_type": one of [text, name, email, phone, number, date, '
                'address, checkbox, radio, signature],\n'
                '  "profile_key": the best matching provided profile key, or "",\n'
                '  "validation": one of [none, email, phone, date, number, iban, zip],\n'
                '  "confidence": a number 0..1.\n'
                f"{keys_hint}{lang_hint}\n"
                'Respond with valid JSON only, as {"fields": [ ... ]} in the same order.'
            ),
        },
        {"role": "user", "content": f"Fields:\n{field_lines}"},
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages,
        use_advanced=False,
        max_tokens=4096,
    )
    fields = result.get("fields", []) if isinstance(result, dict) else []
    return UnderstandFormResponse(fields=fields, remaining=remaining)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _check_ai_configured():
    if not settings.AI_API_KEY:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="AI service not configured. Set AI_API_KEY.",
        )


async def _meter(
    request: Request,
    user: Optional[User],
    db: AsyncSession,
) -> int:
    """Enforce the shared free-tier cap and return the remaining quota.

    Verified-Pro users bypass the cap (returns ``UNLIMITED``). Everyone else is
    counted against the daily limit; raises HTTP 429 once exhausted. Call this
    BEFORE spending an AI request so over-limit callers don't incur cost.
    """
    pro = await is_pro(db, request.headers.get("X-Entitlement-Token"))
    if pro:
        return UNLIMITED
    identity = identity_for(user, request)
    allowed, count = check_and_increment(identity)
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Daily free AI limit reached. Upgrade to Pro for unlimited AI.",
        )
    return max(0, settings.AI_FREE_DAILY_LIMIT - count)
