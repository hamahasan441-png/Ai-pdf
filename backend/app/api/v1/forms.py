"""PDF form (AcroForm) inspection endpoints.

Reading *native* PDF form fields (not OCR heuristics) lets the client fill the
real interactive widgets and keep the output a genuinely fillable PDF — the
capability Acrobat/Foxit/UPDF have and our overlay path lacks. Pure PyMuPDF
parsing, no AI call, so it is not metered.

The heavy import (`fitz`/PyMuPDF) is lazy so the app still boots if the optional
dependency is missing (the endpoint then returns a clean 503).
"""

import logging

from fastapi import APIRouter, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/forms", tags=["Forms"])

# Bound request size so a huge upload can't exhaust memory.
_MAX_PDF_BYTES = 25 * 1024 * 1024


class AcroFormField(BaseModel):
    name: str
    type: str          # text | checkbox | radiobutton | combobox | listbox | signature | ...
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


def _read_acroform(data: bytes) -> dict:
    """Enumerate AcroForm widgets in a PDF. Runs in a threadpool."""
    import fitz  # PyMuPDF — lazy import

    doc = fitz.open(stream=data, filetype="pdf")
    try:
        fields: list[dict] = []
        for page in doc:
            for w in page.widgets():
                flags = w.field_flags or 0
                fields.append(
                    {
                        "name": w.field_name or "",
                        "type": (w.field_type_string or "").lower(),
                        "value": str(w.field_value or ""),
                        "page": page.number,
                        "rect": [w.rect.x0, w.rect.y0, w.rect.x1, w.rect.y1],
                        "options": list(w.choice_values or []),
                        # PDF field-flag bits: 1=ReadOnly, 2=Required.
                        "required": bool(flags & 2),
                        "readonly": bool(flags & 1),
                    }
                )
        return {
            "is_form": bool(doc.is_form_pdf),
            "field_count": len(fields),
            "fields": fields,
        }
    finally:
        doc.close()


@router.post("/acroform/read", response_model=AcroFormResponse)
async def read_acroform(file: UploadFile = File(...)):
    """Read the native AcroForm field graph from an uploaded PDF."""
    data = await file.read()
    if not data:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Empty file"
        )
    if len(data) > _MAX_PDF_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="PDF exceeds the maximum allowed size",
        )

    try:
        result = await run_in_threadpool(_read_acroform, data)
    except ImportError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="PDF form parser is not available on the server.",
        )
    except Exception as e:  # noqa: BLE001 - surface a clean 422 for bad PDFs
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Could not read PDF form: {e}",
        )
    return AcroFormResponse(**result)
