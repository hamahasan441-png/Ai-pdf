"""PDF form (AcroForm) endpoints: read native fields + fill them.

These enable the client to work with REAL interactive PDF form widgets (not just
OCR-detected overlays) — the capability Adobe/Foxit/UPDF have. Pure PyMuPDF
parsing + filling, no AI, so they are NOT metered.

The heavy import (`fitz`/PyMuPDF) is lazy so the app still boots if the
dependency is missing (endpoint returns a clean 503).
"""

import logging

from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool
from fastapi.responses import Response

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

from app.services.ai.batch_processor import batch_processor  # noqa: E402


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
