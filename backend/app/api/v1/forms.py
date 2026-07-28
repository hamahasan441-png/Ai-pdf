"""PDF form (AcroForm) endpoints: read native fields + fill them + AI understanding.

These enable the client to work with REAL interactive PDF form widgets (not just
OCR-detected overlays) — the capability Adobe/Foxit/UPDF have. Pure PyMuPDF
parsing + filling for AcroForms (not metered). An AI-powered ``understand-form``
endpoint handles semantic fallback for flat/scanned PDFs where heuristics are unsure.

The heavy import (`fitz`/PyMuPDF) is lazy so the app still boots if the
dependency is missing (endpoint returns a clean 503).
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool
from fastapi.responses import Response

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.batch_processor import batch_processor
from app.services.ai.provider import ai_provider
from app.services.ai.usage_limiter import (
    UNLIMITED,
    check_and_increment_tiered,
    identity_for,
)
from app.services.billing.quota_tiers import get_quota

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/forms", tags=["Forms"])

_MAX_PDF_BYTES = 25 * 1024 * 1024  # 25 MB


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class AcroFormField(BaseModel):
    name: str
    type: str          # text | checkbox | radiobutton | combobox | listbox | signature
    value: str = ""
    page: int          # 0-based page index
    rect: list[float]  # [x0, y0, x1, y1] in PDF points
    options: list[str] = []  # choices for combo/list fields
    required: bool = False
    readonly: bool = False


class AcroFormResponse(BaseModel):
    is_form: bool
    field_count: int
    fields: list[AcroFormField]


# ---------------------------------------------------------------------------
# Read endpoint
# ---------------------------------------------------------------------------

def _read_acroform(data: bytes) -> dict:
    """Enumerate AcroForm widgets in a PDF. Runs in a threadpool."""
    import fitz

    doc = fitz.open(stream=data, filetype="pdf")
    try:
        fields: list[dict] = []
        for page in doc:
            for w in page.widgets():
                flags = w.field_flags or 0
                fields.append({
                    "name": w.field_name or "",
                    "type": (w.field_type_string or "").lower(),
                    "value": str(w.field_value or ""),
                    "page": page.number,
                    "rect": [w.rect.x0, w.rect.y0, w.rect.x1, w.rect.y1],
                    "options": list(w.choice_values or []),
                    "required": bool(flags & 2),
                    "readonly": bool(flags & 1),
                })
        return {
            "is_form": bool(doc.is_form_pdf),
            "field_count": len(fields),
            "fields": fields,
        }
    finally:
        doc.close()


@router.post("/acroform/read", response_model=AcroFormResponse)
async def read_acroform(file: UploadFile = File(...)):
    """Read native AcroForm field graph from an uploaded PDF."""
    data = await file.read()
    if not data:
        raise HTTPException(status_code=422, detail="Empty file")
    if len(data) > _MAX_PDF_BYTES:
        raise HTTPException(status_code=413, detail="PDF exceeds maximum size")
    try:
        result = await run_in_threadpool(_read_acroform, data)
    except ImportError:
        raise HTTPException(status_code=503, detail="PDF form parser not available")
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Could not read PDF form: {e}")
    return AcroFormResponse(**result)


# ---------------------------------------------------------------------------
# Fill endpoint
# ---------------------------------------------------------------------------

def _fill_acroform(data: bytes, values: dict[str, str]) -> bytes:
    """Fill AcroForm fields and return the resulting PDF bytes.

    Args:
        data: Original PDF bytes.
        values: {field_name: value_to_set} for each field to fill.

    Returns:
        Filled PDF bytes (with widgets flattened for viewing).
    """
    import fitz

    doc = fitz.open(stream=data, filetype="pdf")
    try:
        filled_count = 0
        for page in doc:
            for w in page.widgets():
                name = w.field_name or ""
                if name in values:
                    field_type = (w.field_type_string or "").lower()
                    val = values[name]
                    if field_type == "checkbox":
                        # Checkbox: "true"/"yes"/"1" → checked; else unchecked.
                        w.field_value = val.lower() in ("true", "yes", "1", "on")
                    else:
                        w.field_value = val
                    w.update()
                    filled_count += 1
        if filled_count == 0:
            logger.warning("No matching fields were filled (names may not match)")
        return doc.tobytes(deflate=True)
    finally:
        doc.close()


@router.post("/acroform/fill")
async def fill_acroform(
    file: UploadFile = File(...),
    values_json: str = Form(..., description='JSON object: {"field_name": "value", ...}'),
):
    """Fill a PDF's native AcroForm fields and return the filled PDF.

    Upload the PDF as `file` and pass field values as a JSON string in
    `values_json` (form field, not body JSON, because multipart).

    Returns the filled PDF as `application/pdf` bytes.
    """
    import json

    data = await file.read()
    if not data:
        raise HTTPException(status_code=422, detail="Empty file")
    if len(data) > _MAX_PDF_BYTES:
        raise HTTPException(status_code=413, detail="PDF exceeds maximum size")

    try:
        values = json.loads(values_json)
    except (json.JSONDecodeError, TypeError) as e:
        raise HTTPException(status_code=422, detail=f"Invalid values_json: {e}")

    if not isinstance(values, dict):
        raise HTTPException(status_code=422, detail="values_json must be a JSON object")

    try:
        filled_bytes = await run_in_threadpool(_fill_acroform, data, values)
    except ImportError:
        raise HTTPException(status_code=503, detail="PDF form filler not available")
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Could not fill PDF form: {e}")

    return Response(
        content=filled_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=filled.pdf"},
    )


# ---------------------------------------------------------------------------
# Batch endpoint
# ---------------------------------------------------------------------------


class BatchFieldInput(BaseModel):
    label: str
    type: str = "text"


class BatchDocumentInput(BaseModel):
    name: str
    fields: list[BatchFieldInput]


class BatchFillRequest(BaseModel):
    """Fill multiple forms with one profile in a single call.

    ``documents`` is a list of form descriptors — each contains the form name
    and the fields detected on it (by the on-device OCR pipeline). ``profile``
    is the user's saved key→value store (encrypted on-device; the server only
    sees plaintext for the duration of the request). ``field_mappings`` lets
    the client send explicit ``{label: profile_key}`` overrides for ambiguous
    fields.
    """
    documents: list[BatchDocumentInput]
    profile: dict[str, str]
    field_mappings: dict[str, str] = {}


class BatchFillResultItem(BaseModel):
    doc_index: int
    doc_name: str
    fields_detected: int
    fields_filled: int
    fields_uncertain: int
    filled_values: dict
    validation_errors: list


class BatchFillResponse(BaseModel):
    results: list[BatchFillResultItem]
    total_forms: int
    total_filled: int


class BatchFillV2ResultItem(BaseModel):
    doc: str
    name: str
    status: str  # success, partial, failed
    filled_count: int
    errors: list


class BatchFillV2Response(BaseModel):
    results: list[BatchFillV2ResultItem]
    total: int
    succeeded: int
    failed: int
    partial: int


_MAX_BATCH_DOCS = 50  # Reasonable cap to avoid runaway CPU usage.


@router.post("/batch", response_model=BatchFillResponse)
async def batch_fill_forms(request: BatchFillRequest):
    """Fill multiple forms with a single profile in one round-trip.

    The server runs the same field-detection → profile-matching → validation
    pipeline that single-form fill uses, but over N documents at once. The
    response lists the filled values for each form so the client can issue
    targeted ``/acroform/fill`` calls or apply overlay annotations.

    This endpoint is NOT metered (no AI model is involved; it's pure matching
    logic). It is capped at ``_MAX_BATCH_DOCS`` documents per call.
    """
    if len(request.documents) > _MAX_BATCH_DOCS:
        raise HTTPException(
            status_code=422,
            detail=f"Batch size exceeds maximum ({_MAX_BATCH_DOCS} documents).",
        )

    docs = [{"name": d.name, "fields": [f.model_dump() for f in d.fields]} for d in request.documents]
    raw_results = batch_processor.process_batch(
        docs,
        request.profile,
        request.field_mappings or {},
    )

    results = [
        BatchFillResultItem(
            doc_index=r.doc_index,
            doc_name=r.doc_name,
            fields_detected=r.fields_detected,
            fields_filled=r.fields_filled,
            fields_uncertain=r.fields_uncertain,
            filled_values=r.filled_values,
            validation_errors=r.validation_errors,
        )
        for r in raw_results
    ]
    return BatchFillResponse(
        results=results,
        total_forms=len(results),
        total_filled=sum(r.fields_filled for r in results),
    )


@router.post("/batch/v2", response_model=BatchFillV2Response)
async def batch_fill_forms_v2(request: BatchFillRequest):
    """Fill multiple forms — V2 with per-doc status + error report (E3.6).

    Returns for each doc:
    - doc: index
    - name: doc name
    - status: success (all fields filled), partial (some filled), failed (none filled)
    - filled_count: number filled
    - errors: list of {field, error} validation errors

    Frontend shows progress bar + cancel + error report with retry failed only.
    Uses batch_processor with bounded concurrency (future: WorkManager for large).
    """
    if len(request.documents) > _MAX_BATCH_DOCS:
        raise HTTPException(
            status_code=422,
            detail=f"Batch size exceeds maximum ({_MAX_BATCH_DOCS} documents).",
        )

    docs = [{"name": d.name, "fields": [f.model_dump() for f in d.fields]} for d in request.documents]
    raw_results = batch_processor.process_batch(
        docs,
        request.profile,
        request.field_mappings or {},
    )

    v2_results = []
    succeeded = failed = partial = 0
    for r in raw_results:
        if r.fields_filled == 0:
            status = "failed"
            failed += 1
        elif r.fields_filled < r.fields_detected:
            status = "partial"
            partial += 1
        else:
            status = "success"
            succeeded += 1

        v2_results.append(
            BatchFillV2ResultItem(
                doc=str(r.doc_index),
                name=r.doc_name,
                status=status,
                filled_count=r.fields_filled,
                errors=r.validation_errors,
            )
        )

    return BatchFillV2Response(
        results=v2_results,
        total=len(v2_results),
        succeeded=succeeded,
        failed=failed,
        partial=partial,
    )


# ---------------------------------------------------------------------------
# AI semantic form understanding (Pillar 3 — hybrid detection fallback)
# ---------------------------------------------------------------------------

class UnderstandFormFieldInput(BaseModel):
    """A single field label/text as detected by OCR heuristics."""
    label: str = Field(..., max_length=500, description="OCR-detected field label text")
    type_hint: str = Field("unknown", description="Heuristic type guess: text|checkbox|date|signature|unknown")
    confidence: float = Field(0.0, ge=0.0, le=1.0, description="Heuristic confidence score (0–1)")


class UnderstandFormRequest(BaseModel):
    """Batch of uncertain form fields sent to AI for semantic classification.

    The client sends ONLY fields whose heuristic confidence is below a threshold
    (e.g. < 0.6), keeping the payload small. The AI returns a best-guess semantic
    type and the most likely user-profile key for each.
    """
    fields: list[UnderstandFormFieldInput] = Field(..., min_length=1, max_length=50)
    document_context: str = Field(
        "",
        max_length=2000,
        description="A short description or title of the document for context",
    )
    language: str = Field("auto", description="Document language hint, or 'auto'")


class UnderstandFormFieldResult(BaseModel):
    label: str
    semantic_type: str = Field(
        ...,
        description=(
            "Canonical field type: name|first_name|last_name|email|phone|address|"
            "city|country|postal_code|date_of_birth|date|signature|checkbox|"
            "id_number|organization|job_title|iban|amount|other"
        ),
    )
    profile_key: str = Field(
        "",
        description="Recommended user-profile key to map this field to (e.g. 'full_name', 'email')",
    )
    confidence: float = Field(0.0, ge=0.0, le=1.0)
    reason: str = Field("", description="Short explanation of the classification")


class UnderstandFormResponse(BaseModel):
    fields: list[UnderstandFormFieldResult]
    remaining: int = -1


@router.post("/understand-form", response_model=UnderstandFormResponse)
async def understand_form(
    req: UnderstandFormRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """AI semantic fallback for ambiguous form-field classification.

    When on-device heuristics are unsure about a field's type or the right
    profile mapping (confidence < threshold), the client sends those fields here
    for AI-powered semantic understanding. Only the labels (not the document) are
    sent, preserving the privacy-first design.

    The AI returns a canonical ``semantic_type``, a recommended ``profile_key``,
    a confidence score, and a short reason for each field.

    Metered via the tiered quota system (free / basic / Pro).
    """
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    # Tiered metering — Pro is unlimited.
    token = request.headers.get("X-Entitlement-Token")
    _tier, limit = await get_quota(db, token)
    remaining = UNLIMITED
    if limit is not None:
        identity = identity_for(user, request)
        allowed, count = check_and_increment_tiered(identity, limit)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, limit - count)

    lang_hint = f" The document language is {req.language}." if req.language != "auto" else ""
    ctx_hint = f" Document context: {req.document_context}." if req.document_context else ""

    fields_payload = [
        {"label": f.label, "type_hint": f.type_hint, "confidence": f.confidence}
        for f in req.fields
    ]

    import json
    messages = [
        {
            "role": "system",
            "content": (
                "You are a form-field semantic classifier. Given a list of form field "
                "labels (from OCR), classify each one with:\n"
                "- semantic_type: one of name|first_name|last_name|email|phone|address|"
                "city|country|postal_code|date_of_birth|date|signature|checkbox|"
                "id_number|organization|job_title|iban|amount|other\n"
                "- profile_key: the most likely user-profile key (e.g. full_name, email, "
                "phone, address, city, country, postal_code, date_of_birth, id_number, "
                "organization, job_title, iban) or empty string if none applies\n"
                "- confidence: 0.0–1.0 how sure you are\n"
                "- reason: 1-sentence explanation\n\n"
                f"Respond ONLY with valid JSON: "
                '{"fields": [{"label": "...", "semantic_type": "...", "profile_key": "...", '
                '"confidence": 0.9, "reason": "..."}]}'
                f"{lang_hint}{ctx_hint}"
            ),
        },
        {
            "role": "user",
            "content": f"Fields to classify:\n{json.dumps(fields_payload, ensure_ascii=False)}",
        },
    ]

    result = await ai_provider.chat_completion_json(
        messages=messages, use_advanced=False, max_tokens=2048
    )

    raw_fields = result.get("fields", []) if isinstance(result, dict) else []
    # Validate and sanitise each result; drop malformed entries.
    output: list[UnderstandFormFieldResult] = []
    label_set = {f.label for f in req.fields}
    for item in raw_fields:
        if not isinstance(item, dict):
            continue
        label = str(item.get("label", ""))
        if label not in label_set:
            continue  # model hallucinated a label — drop it
        try:
            conf = float(item.get("confidence", 0.0))
            conf = max(0.0, min(1.0, conf))
        except (TypeError, ValueError):
            conf = 0.0
        output.append(
            UnderstandFormFieldResult(
                label=label,
                semantic_type=str(item.get("semantic_type", "other")) or "other",
                profile_key=str(item.get("profile_key", "")),
                confidence=conf,
                reason=str(item.get("reason", "")),
            )
        )

    # For any requested field the model didn't return, add a low-confidence "other".
    returned_labels = {r.label for r in output}
    for f in req.fields:
        if f.label not in returned_labels:
            output.append(
                UnderstandFormFieldResult(
                    label=f.label,
                    semantic_type="other",
                    profile_key="",
                    confidence=0.0,
                    reason="Model did not return a classification for this field.",
                )
            )

    return UnderstandFormResponse(fields=output, remaining=remaining)
