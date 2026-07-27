"""Document AI endpoints — Chat with PDF, Summarize, Translate, Rewrite, Extract, Understand Form.

These endpoints power the app's AI document intelligence features. Every
endpoint is metered using per-plan quota tiers: Pro users are unlimited,
"basic" tier users get a higher daily cap, and free users share the default
cap — all via ``app.services.ai.usage_limiter`` and
``app.services.billing.quota_tiers``.
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from fastapi.responses import StreamingResponse

from app.models.user import User
from app.services.ai.map_reduce_summarizer import (
    map_reduce_summarize,
    stream_map_reduce_summarize,
)
from app.services.ai.provider import ai_provider
from app.services.ai.usage_limiter import (
    UNLIMITED,
    check_and_increment_tiered,
    identity_for,
)

from app.services.billing.quota_tiers import get_quota, get_quota_with_team

# Character threshold above which we switch to map-reduce summarization so the
# full document is covered rather than truncated.
_MAP_REDUCE_THRESHOLD = 12_000

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


class FixOcrRequest(BaseModel):
    text: str = Field(..., max_length=20000,
                      description="Raw OCR output that may contain recognition errors")
    language: str = "auto"


class FixOcrResponse(BaseModel):
    corrected_text: str
    remaining: int = -1


class UnderstandFormFieldInput(BaseModel):
    """A single form field descriptor sent to the understand-form endpoint."""
    label: str = Field(..., max_length=500,
                       description="The field label as detected from the PDF")
    detected_type: str = Field("text",
                               description="Heuristic type hint: text|date|email|phone|number|checkbox|signature")
    confidence: float = Field(1.0, ge=0.0, le=1.0,
                              description="Heuristic confidence (0–1). Low-confidence fields benefit most from AI classification.")


class UnderstandFormFieldResult(BaseModel):
    """AI-enriched classification for one form field."""
    label: str
    semantic_type: str    # e.g. first_name, last_name, email, date_of_birth
    profile_key: str      # key to look up in the user profile (matches profile ontology)
    field_type: str       # text | date | email | phone | number | checkbox | signature | address | select
    confidence: float     # AI confidence 0.0–1.0
    reasoning: str = ""   # brief explanation (trimmed for token efficiency)


class UnderstandFormRequest(BaseModel):
    """Batch of uncertain form field labels to classify semantically."""
    fields: list[UnderstandFormFieldInput] = Field(..., min_length=1, max_length=50,
                                                   description="Fields to classify (max 50 per call)")
    language: str = Field("auto", description="Document language hint (improves classification of non-English labels)")


class UnderstandFormResponse(BaseModel):
    """AI-classified field list ready for profile mapping."""
    fields: list[UnderstandFormFieldResult]
    language_detected: str = ""
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
    """Generate a structured summary of a document.

    For long documents (> ``_MAP_REDUCE_THRESHOLD`` characters) the service
    uses a map-reduce approach: it summarizes each chunk independently and
    then combines those partial summaries into a single coherent result.  This
    prevents the "lost middle" problem of naive context-window truncation.
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    if len(req.document_text) > _MAP_REDUCE_THRESHOLD:
        # Long document — use map-reduce so no content is silently dropped.
        reply = await map_reduce_summarize(
            req.document_text,
            style=req.style,
            language=req.language,
        )
    else:
        style_instruction = {
            "structured": "Provide a structured summary: 1) Document type, 2) Key points (bullets), 3) Important entities, 4) Action items.",
            "brief": "Provide a 2-3 sentence summary capturing the essential information.",
            "bullet": "Provide a bullet-point summary with one key fact per bullet.",
        }.get(req.style, "Summarize clearly and concisely.")

        lang_hint = f" Respond in {req.language}." if req.language != "auto" else ""

        messages = [
            {"role": "system", "content": f"You are an expert document summarizer.{lang_hint}"},
            {"role": "user", "content": f"{style_instruction}\n\nDocument:\n{req.document_text}"},
        ]
        reply = await ai_provider.chat_completion(
            messages=messages,
            temperature=0.2,
            max_tokens=2048,
        )
    return SummarizeResponse(summary=reply, remaining=remaining)


@router.post("/summarize/stream")
async def summarize_document_stream(
    req: SummarizeRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Streaming map-reduce summarization — E2.2 (ENHANCEMENT_BASED_MASTERPLAN).

    Returns Server-Sent Events (SSE) with per-chunk summaries then final:
    - event: chunk -> {"type":"chunk","index":1,"total":5,"summary":"...","page_citation":{}}
    - event: final -> {"type":"final","summary":"...","chunks":5,"cited":[1,2,3,4,5]}

    First chunk streams in <10s (vs waiting for full reduce), enabling progressive UI.
    Uses same metering as /summarize (one quota unit per stream).
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    async def event_generator():
        import json

        # Include remaining in first comment
        yield f": remaining={remaining}\n\n"
        async for chunk in stream_map_reduce_summarize(
            req.document_text, style=req.style, language=req.language
        ):
            data = json.dumps(chunk, ensure_ascii=False)
            yield f"data: {data}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@router.post("/summarize/stream/json")
async def summarize_document_stream_json(
    req: SummarizeRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """JSON-lines variant of streaming for clients that don't support SSE.

    Returns newline-delimited JSON: each line is a chunk event, final line is [DONE].
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    async def json_generator():
        import json

        async for chunk in stream_map_reduce_summarize(
            req.document_text, style=req.style, language=req.language
        ):
            yield json.dumps(chunk, ensure_ascii=False) + "\n"
        yield json.dumps({"type": "done", "remaining": remaining}) + "\n"

    return StreamingResponse(json_generator(), media_type="application/x-ndjson")


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


@router.post("/fix-ocr", response_model=FixOcrResponse)
async def fix_ocr(
    req: FixOcrRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Correct common OCR recognition errors in extracted text.

    Complements the on-device OCR: the client sends raw OCR output and gets back
    a cleaned version (fixed character confusions, merged broken words, restored
    spacing) without altering the actual content.
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    lang_hint = f" The text is in {req.language}." if req.language != "auto" else ""

    messages = [
        {
            "role": "system",
            "content": (
                "You are an OCR post-correction expert. Fix common OCR mistakes in the "
                "user's text: character confusions (rn->m, l->1, O->0, cl->d), missing or "
                "extra spaces, words broken across line breaks, and garbled punctuation."
                f"{lang_hint} Preserve the original wording, numbers, and meaning exactly — "
                "only fix recognition errors. Do not summarize, translate, or add anything. "
                "Return ONLY the corrected text."
            ),
        },
        {"role": "user", "content": req.text},
    ]

    reply = await ai_provider.chat_completion(
        messages=messages,
        temperature=0.0,
        max_tokens=4096,
    )
    return FixOcrResponse(corrected_text=reply, remaining=remaining)


@router.post("/understand-form", response_model=UnderstandFormResponse)
async def understand_form(
    req: UnderstandFormRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Semantically classify uncertain form field labels and map them to profile keys.

    The on-device heuristic pipeline (OCR + ontology matching) handles the
    majority of fields instantly and offline. When a field's heuristic
    confidence is low, the client batches those uncertain labels here for AI
    semantic classification — only the labels are sent, never the document.

    The AI maps each label to a standardised ``profile_key`` (e.g. "Vorname" →
    ``first_name``) so the caller can look up the matching value in the user's
    encrypted local profile without any further prompting.

    Costs one metered AI call regardless of the number of fields (cheap:
    all labels fit in one prompt).
    """
    _check_ai_configured()
    remaining = await _meter(request, user, db)

    lang_hint = f" The form is in {req.language}." if req.language != "auto" else ""

    fields_json = [
        {"label": f.label, "detected_type": f.detected_type, "confidence": round(f.confidence, 2)}
        for f in req.fields
    ]

    messages = [
        {
            "role": "system",
            "content": (
                "You are a multilingual form field classification expert. "
                "Given a list of form field descriptors, classify each one and map it to a "
                "standardised profile key so the client can auto-fill it from the user's profile.\n\n"
                "Return a single JSON object with:\n"
                '  "language_detected": detected language of the labels (e.g. "German", "English"),\n'
                '  "fields": array of objects, one per input field, each with:\n'
                '    "label": the original label (unchanged),\n'
                '    "semantic_type": short English label (snake_case), e.g. first_name, last_name,\n'
                '      email, phone, date_of_birth, address, city, zip, country, employer,\n'
                '      job_title, national_id, iban, signature, checkbox, unknown,\n'
                '    "profile_key": the key to look up in the user profile (usually same as semantic_type),\n'
                '    "field_type": one of: text, date, email, phone, number, checkbox, signature, address, select,\n'
                '    "confidence": float 0.0–1.0 reflecting your certainty,\n'
                '    "reasoning": one short sentence explaining the mapping.\n\n'
                f"Base classification on the label text only.{lang_hint} "
                "Respond with valid JSON only — no markdown, no explanation outside the JSON."
            ),
        },
        {
            "role": "user",
            "content": f"Classify these form fields:\n{fields_json}",
        },
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages,
        use_advanced=False,
        max_tokens=2048,
    )

    # Parse and validate the response gracefully.
    raw_fields = result.get("fields", []) if isinstance(result, dict) else []
    language_detected = result.get("language_detected", "") if isinstance(result, dict) else ""
    classified: list[UnderstandFormFieldResult] = []
    for item in raw_fields:
        if not isinstance(item, dict):
            continue
        label = item.get("label", "")
        if not label:
            continue
        classified.append(
            UnderstandFormFieldResult(
                label=label,
                semantic_type=str(item.get("semantic_type", "unknown"))[:100],
                profile_key=str(item.get("profile_key", item.get("semantic_type", "unknown")))[:100],
                field_type=str(item.get("field_type", "text"))[:50],
                confidence=float(item.get("confidence", 0.5)),
                reasoning=str(item.get("reasoning", ""))[:300],
            )
        )

    # Fall back: for any input label the AI omitted, add an unknown entry.
    returned_labels = {r.label for r in classified}
    for field in req.fields:
        if field.label not in returned_labels:
            classified.append(
                UnderstandFormFieldResult(
                    label=field.label,
                    semantic_type="unknown",
                    profile_key="unknown",
                    field_type=field.detected_type,
                    confidence=0.0,
                    reasoning="Not classified by AI",
                )
            )

    return UnderstandFormResponse(
        fields=classified,
        language_detected=language_detected,
        remaining=remaining,
    )


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
    """Enforce the per-plan daily cap and return the remaining quota.

    E8.1: If X-Team-Id header present and team has ai_daily_quota, that quota
    is enforced via a team-scoped counter (team:{id}:{date}) — shared pool.

    Tier resolution:
    - Team quota (if header + team has quota) → team limit
    - Pro (monthly/yearly/lifetime) → unlimited (returns ``UNLIMITED``).
    - Basic → ``AI_BASIC_DAILY_LIMIT`` per day.
    - Free (no/invalid token) → ``AI_FREE_DAILY_LIMIT`` per day.

    Raises HTTP 429 once the daily limit is exhausted. Call this BEFORE
    spending an AI request so over-limit callers don't incur cost.
    """
    token = request.headers.get("X-Entitlement-Token")
    team_id_header = request.headers.get("X-Team-Id")

    tier = "free"
    limit = None
    source = "free"

    if team_id_header:
        try:
            import uuid

            team_uuid = uuid.UUID(team_id_header)
            tier, limit, source = await get_quota_with_team(db, token, team_uuid)
        except Exception:
            # Invalid team id header — fall back to normal quota
            tier, limit = await get_quota(db, token)
            source = "entitlement" if token else "free"
    else:
        tier, limit = await get_quota(db, token)
        source = "entitlement" if token else "free"

    if limit is None:
        return UNLIMITED

    # Identity: team-scoped counter if team quota, else user/ip
    if source == "team" and team_id_header:
        identity = f"team:{team_id_header}"
    else:
        identity = identity_for(user, request)

    allowed, count = check_and_increment_tiered(identity, limit)
    if not allowed:
        detail = (
            f"Team daily AI limit reached ({limit})."
            if source == "team"
            else "Daily AI limit reached. Upgrade to Pro for unlimited AI."
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=detail,
        )
    return max(0, limit - count)
