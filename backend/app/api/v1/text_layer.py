"""PDF text layer extraction endpoint.

Extracts positioned text elements from a PDF's native content stream (not OCR).
Returns the exact text, position, and font info for each text block — enabling
text selection, copy, and search in the client.
"""

import logging

from fastapi import APIRouter, File, HTTPException, UploadFile
from pydantic import BaseModel
from starlette.concurrency import run_in_threadpool

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/document-ai", tags=["Document AI"])

_MAX_PDF_BYTES = 25 * 1024 * 1024


class TextElement(BaseModel):
    text: str
    x: float       # normalised 0..1
    y: float
    w: float
    h: float
    fontSize: float  # in pt
    fontName: str = ""
    bold: bool = False
    italic: bool = False
    page: int = 0


class TextLayerResponse(BaseModel):
    page_count: int
    elements: list[TextElement]


def _extract_text_layer(data: bytes, page_number: int = -1) -> dict:
    """Extract positioned text from PDF using PyMuPDF."""
    import fitz

    doc = fitz.open(stream=data, filetype="pdf")
    try:
        elements = []
        pages_to_process = (
            range(doc.page_count) if page_number < 0
            else [page_number] if 0 <= page_number < doc.page_count
            else []
        )
        for pg_idx in pages_to_process:
            page = doc[pg_idx]
            pw, ph = page.rect.width, page.rect.height
            if pw == 0 or ph == 0:
                continue
            blocks = page.get_text("dict", flags=fitz.TEXT_PRESERVE_WHITESPACE)["blocks"]
            for block in blocks:
                if block.get("type") != 0:  # text block only
                    continue
                for line in block.get("lines", []):
                    for span in line.get("spans", []):
                        text = span.get("text", "").strip()
                        if not text:
                            continue
                        bbox = span.get("bbox", (0, 0, 0, 0))
                        font = span.get("font", "")
                        size = span.get("size", 12)
                        flags = span.get("flags", 0)
                        elements.append({
                            "text": text,
                            "x": bbox[0] / pw,
                            "y": bbox[1] / ph,
                            "w": (bbox[2] - bbox[0]) / pw,
                            "h": (bbox[3] - bbox[1]) / ph,
                            "fontSize": size,
                            "fontName": font,
                            "bold": bool(flags & 16),
                            "italic": bool(flags & 2),
                            "page": pg_idx,
                        })
        return {"page_count": doc.page_count, "elements": elements}
    finally:
        doc.close()


@router.post("/text-layer", response_model=TextLayerResponse)
async def extract_text_layer(
    file: UploadFile = File(...),
    page: int = -1,
):
    """Extract the native text layer from a PDF (positioned text elements).

    - page=-1: extract from all pages
    - page=N: extract from page N only (0-based)

    Not metered (pure parsing, no AI). Returns normalised coordinates (0..1).
    """
    data = await file.read()
    if not data:
        raise HTTPException(status_code=422, detail="Empty file")
    if len(data) > _MAX_PDF_BYTES:
        raise HTTPException(status_code=413, detail="PDF exceeds maximum size")
    try:
        result = await run_in_threadpool(_extract_text_layer, data, page)
    except ImportError:
        raise HTTPException(status_code=503, detail="PDF parser not available")
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Could not extract text: {e}")
    return TextLayerResponse(**result)
