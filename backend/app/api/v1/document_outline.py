"""Document outline/TOC extraction endpoint.

Extracts the document's structural outline (table of contents / heading
hierarchy) either from native PDF bookmarks (if present) or via AI analysis
of the text content. Powers a "Document Outline" panel in the app.
"""

from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

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


class OutlineItem(BaseModel):
    title: str
    page: int = 0   # 0-based page number (0 if unknown)
    level: int = 1  # heading depth (1 = top-level)
    children: list["OutlineItem"] = []


class OutlineResponse(BaseModel):
    source: str  # "bookmarks" | "ai"
    items: list[OutlineItem]
    remaining: int = -1


def _extract_bookmarks(data: bytes) -> list[dict] | None:
    """Try to extract native PDF bookmarks/TOC via PyMuPDF."""
    try:
        import fitz
        doc = fitz.open(stream=data, filetype="pdf")
        try:
            toc = doc.get_toc(simple=True)  # [[level, title, page], ...]
            if not toc:
                return None
            return [
                {"title": entry[1], "page": max(0, entry[2] - 1), "level": entry[0], "children": []}
                for entry in toc
            ]
        finally:
            doc.close()
    except (ImportError, Exception):
        return None


@router.post("/outline", response_model=OutlineResponse)
async def extract_outline(
    file: UploadFile = File(None),
    document_text: str = "",
    request: Request = None,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Extract document outline (TOC/heading structure).

    Two modes:
    1. Upload a PDF file → tries native bookmarks first (free, no AI), falls
       back to AI-based heading extraction if no bookmarks.
    2. Send document_text → AI extracts headings from the text.
    """
    # Mode 1: PDF file with native bookmarks
    if file and file.filename:
        data = await file.read()
        if data:
            bookmarks = await run_in_threadpool(_extract_bookmarks, data)
            if bookmarks:
                return OutlineResponse(source="bookmarks", items=bookmarks, remaining=UNLIMITED)
            # No bookmarks — fall through to AI extraction using the text
            # (caller should also send document_text for this fallback)

    # Mode 2: AI-based outline extraction
    if not document_text:
        raise HTTPException(status_code=422, detail="No document content provided")

    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    # Meter (AI mode only)
    pro = await is_pro(db, request.headers.get("X-Entitlement-Token") if request else None)
    remaining = UNLIMITED
    if not pro:
        identity = identity_for(user, request) if request else "anon"
        allowed, count = check_and_increment(identity)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, settings.AI_FREE_DAILY_LIMIT - count)

    messages = [
        {
            "role": "system",
            "content": (
                "Extract the document's structural outline (headings, sections, "
                "chapters) as a JSON array. Each item: "
                '{"title": "...", "page": 0, "level": 1, "children": []}. '
                "Level 1 = top-level heading, 2 = sub-heading, etc. "
                "If page numbers are visible in the text, include them (0-based). "
                "Return ONLY the JSON array."
            ),
        },
        {"role": "user", "content": f"Document:\n{document_text[:10000]}"},
    ]

    import json
    reply = await ai_provider.chat_completion(
        messages=messages, temperature=0.1, max_tokens=2048
    )
    try:
        items = json.loads(reply)
        if not isinstance(items, list):
            items = []
    except json.JSONDecodeError:
        items = []

    return OutlineResponse(source="ai", items=items, remaining=remaining)
