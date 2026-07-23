"""Multi-document chat endpoint — ask questions across multiple documents.

Enables cross-document reasoning: the user indexes multiple documents, then asks
questions that span them (e.g. "compare the terms in invoice A vs contract B").
Uses the server-side MultiDocBm25Index for retrieval + the AI provider for
synthesis.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.multi_doc_index import MultiDocBm25Index
from app.services.ai.provider import ai_provider
from app.services.ai.usage_limiter import (
    UNLIMITED,
    check_and_increment_tiered,
    identity_for,
)
from app.services.billing.quota_tiers import get_quota

router = APIRouter(prefix="/document-ai", tags=["Document AI"])

# Per-session in-memory indexes (keyed by a client-provided session_id).
# In production this would be backed by Redis with TTL; for now in-memory is
# fine (stateless between server restarts, private by design).
_sessions: dict[str, MultiDocBm25Index] = {}
_MAX_SESSIONS = 100


class IndexDocumentRequest(BaseModel):
    session_id: str = Field(..., max_length=64)
    doc_id: str = Field(..., max_length=128)
    doc_name: str = Field(..., max_length=256)
    pages: dict[int, str] = Field(..., description="Page number → extracted text")


class IndexDocumentResponse(BaseModel):
    chunks_added: int
    total_chunks: int
    docs_indexed: int


class MultiDocChatRequest(BaseModel):
    session_id: str = Field(..., max_length=64)
    question: str = Field(..., max_length=2000)
    top_k: int = Field(5, ge=1, le=20)
    doc_filter: Optional[str] = None


class MultiDocChatResponse(BaseModel):
    answer: str
    citations: list[dict] = []  # [{doc_name, page, snippet}]
    remaining: int = -1


@router.post("/multi-doc/index", response_model=IndexDocumentResponse)
async def index_document(req: IndexDocumentRequest):
    """Add a document to the multi-doc index for a session."""
    if len(_sessions) >= _MAX_SESSIONS and req.session_id not in _sessions:
        # Evict oldest session (simple LRU — first key)
        oldest = next(iter(_sessions))
        del _sessions[oldest]

    idx = _sessions.setdefault(req.session_id, MultiDocBm25Index())
    added = idx.add_document(
        doc_id=req.doc_id,
        doc_name=req.doc_name,
        pages={int(k): v for k, v in req.pages.items()},
    )
    return IndexDocumentResponse(
        chunks_added=added,
        total_chunks=idx.chunk_count,
        docs_indexed=len(idx.doc_ids),
    )


@router.post("/multi-doc/chat", response_model=MultiDocChatResponse)
async def multi_doc_chat(
    req: MultiDocChatRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Ask a question across multiple indexed documents (grounded, cited)."""
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")

    idx = _sessions.get(req.session_id)
    if idx is None or idx.chunk_count == 0:
        raise HTTPException(status_code=404, detail="No documents indexed for this session")

    # Meter
    token = request.headers.get("X-Entitlement-Token")
    _tier, limit = await get_quota(db, token)
    remaining = UNLIMITED
    if limit is not None:
        identity = identity_for(user, request)
        allowed, count = check_and_increment_tiered(identity, limit)
        if not allowed:
            raise HTTPException(status_code=429, detail="Daily limit reached")
        remaining = max(0, limit - count)

    # Retrieve relevant passages
    passages = idx.search(req.question, top_k=req.top_k, doc_filter=req.doc_filter)
    if not passages:
        return MultiDocChatResponse(
            answer="I could not find relevant information in the indexed documents.",
            citations=[],
            remaining=remaining,
        )

    # Build grounded context
    context_lines = []
    citations = []
    for p in passages:
        context_lines.append(f"[{p.doc_name}, page {p.page}]: {p.text}")
        citations.append({"doc_name": p.doc_name, "page": p.page, "snippet": p.text[:200]})

    context = "\n---\n".join(context_lines)

    messages = [
        {
            "role": "system",
            "content": (
                "You are a document assistant answering questions about multiple documents. "
                "Answer based ONLY on the provided context. Cite the document name and page "
                "number for each fact. If the answer is not in the context, say so.\n\n"
                f"Context from {len(idx.doc_ids)} documents:\n{context}"
            ),
        },
        {"role": "user", "content": req.question},
    ]

    reply = await ai_provider.chat_completion(
        messages=messages, temperature=0.2, max_tokens=2048
    )
    return MultiDocChatResponse(answer=reply, citations=citations, remaining=remaining)


@router.delete("/multi-doc/session/{session_id}")
async def clear_session(session_id: str):
    """Clear an indexed session (free memory)."""
    if session_id in _sessions:
        _sessions[session_id].clear()
        del _sessions[session_id]
    return {"status": "cleared"}
