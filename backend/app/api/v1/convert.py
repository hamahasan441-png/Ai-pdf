"""PDF -> Office conversion endpoints (Word / Excel / PowerPoint).

Each endpoint accepts a PDF upload and streams back the converted file. Heavy
conversion runs in a threadpool so it never blocks the event loop. If an
optional converter dependency is missing, a clear 503 is returned.
"""

import tempfile
import uuid
from pathlib import Path

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import Response
from starlette.concurrency import run_in_threadpool

from app.core.config import settings
from app.core.exceptions import (
    DocumentProcessingError,
    FileSizeLimitError,
    ValidationError,
)
from app.services.convert import converter

router = APIRouter()

_DOCX = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
_PPTX = "application/vnd.openxmlformats-officedocument.presentationml.presentation"


async def _save_pdf(file: UploadFile) -> str:
    content = await file.read()
    if len(content) > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
        raise FileSizeLimitError(settings.MAX_UPLOAD_SIZE_MB)
    name = (file.filename or "").lower()
    if file.content_type != "application/pdf" and not name.endswith(".pdf"):
        raise ValidationError("Only PDF files can be converted")
    tmp = Path(tempfile.gettempdir()) / f"conv_{uuid.uuid4()}.pdf"
    tmp.write_bytes(content)
    return str(tmp)


def _download(data: bytes, filename: str, media_type: str) -> Response:
    return Response(
        content=data,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


async def _run(convert_fn, pdf_path: str) -> bytes:
    try:
        return await run_in_threadpool(convert_fn, pdf_path)
    except ImportError as e:
        raise DocumentProcessingError(
            f"Conversion library not installed on the server: {e}"
        )
    except Exception as e:  # noqa: BLE001 - surface a clean error to the client
        raise DocumentProcessingError(f"Conversion failed: {e}")
    finally:
        Path(pdf_path).unlink(missing_ok=True)


@router.post("/pdf-to-word")
async def pdf_to_word(file: UploadFile = File(...)):
    """Convert a PDF to an editable Word (.docx) document."""
    pdf_path = await _save_pdf(file)
    stem = Path(file.filename or "document").stem
    data = await _run(converter.pdf_to_docx, pdf_path)
    return _download(data, f"{stem}.docx", _DOCX)


@router.post("/pdf-to-excel")
async def pdf_to_excel(file: UploadFile = File(...)):
    """Convert a PDF to Excel (.xlsx), extracting tables (text fallback)."""
    pdf_path = await _save_pdf(file)
    stem = Path(file.filename or "document").stem
    data = await _run(converter.pdf_to_xlsx, pdf_path)
    return _download(data, f"{stem}.xlsx", _XLSX)


@router.post("/pdf-to-ppt")
async def pdf_to_ppt(file: UploadFile = File(...)):
    """Convert a PDF to PowerPoint (.pptx) — one page image per slide."""
    pdf_path = await _save_pdf(file)
    stem = Path(file.filename or "document").stem
    data = await _run(converter.pdf_to_pptx, pdf_path)
    return _download(data, f"{stem}.pptx", _PPTX)
