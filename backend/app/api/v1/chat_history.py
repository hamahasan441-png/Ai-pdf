"""Chat history endpoints (Part 7.3 — Developer Platform).

Persist and retrieve AI chat conversations so users can resume them across
sessions. Create → append messages → list → get → delete.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.db.database import get_db
from app.models.chat_history import ChatMessage, ChatSession
from app.models.user import User
from app.schemas.chat_history import (
    AppendMessageRequest,
    CreateSessionRequest,
    MessageResponse,
    SessionDetailResponse,
    SessionResponse,
)

router = APIRouter(prefix="/chat-history", tags=["Chat History"])

_MAX_SESSIONS = 200


@router.post("", response_model=SessionResponse, status_code=201)
async def create_session(
    request: CreateSessionRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new chat session."""
    # Enforce per-user cap
    count = (
        await db.execute(
            select(func.count()).select_from(ChatSession).where(ChatSession.owner_id == user.id)
        )
    ).scalar_one()
    if count >= _MAX_SESSIONS:
        raise HTTPException(
            status_code=409,
            detail=f"Maximum {_MAX_SESSIONS} sessions reached. Delete old sessions first.",
        )

    session = ChatSession(
        owner_id=user.id,
        title=request.title,
        document_id=request.document_id,
    )
    db.add(session)
    await db.flush()

    return SessionResponse(
        id=str(session.id),
        title=session.title,
        document_id=session.document_id,
        message_count=0,
        created_at=session.created_at,
        updated_at=session.updated_at,
    )


@router.get("", response_model=list[SessionResponse])
async def list_sessions(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List chat sessions for the authenticated user (newest first)."""
    sessions = (
        await db.execute(
            select(ChatSession)
            .where(ChatSession.owner_id == user.id)
            .order_by(ChatSession.updated_at.desc())
        )
    ).scalars().all()

    out: list[SessionResponse] = []
    for s in sessions:
        msg_count = (
            await db.execute(
                select(func.count())
                .select_from(ChatMessage)
                .where(ChatMessage.session_id == s.id)
            )
        ).scalar_one()
        out.append(
            SessionResponse(
                id=str(s.id),
                title=s.title,
                document_id=s.document_id,
                message_count=msg_count,
                created_at=s.created_at,
                updated_at=s.updated_at,
            )
        )
    return out


@router.get("/{session_id}", response_model=SessionDetailResponse)
async def get_session(
    session_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a chat session with all its messages."""
    session = await _require_session(db, session_id, user.id)
    messages = (
        await db.execute(
            select(ChatMessage)
            .where(ChatMessage.session_id == session.id)
            .order_by(ChatMessage.seq)
        )
    ).scalars().all()

    return SessionDetailResponse(
        id=str(session.id),
        title=session.title,
        document_id=session.document_id,
        messages=[
            MessageResponse(
                id=str(m.id),
                role=m.role,
                content=m.content,
                created_at=m.created_at,
            )
            for m in messages
        ],
        created_at=session.created_at,
        updated_at=session.updated_at,
    )


@router.post("/{session_id}/messages", response_model=MessageResponse, status_code=201)
async def append_message(
    session_id: uuid.UUID,
    request: AppendMessageRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Append a message to a chat session."""
    session = await _require_session(db, session_id, user.id)

    # Get next sequence number
    max_seq = (
        await db.execute(
            select(func.max(ChatMessage.seq)).where(ChatMessage.session_id == session.id)
        )
    ).scalar_one()
    next_seq = (max_seq or 0) + 1

    msg = ChatMessage(
        session_id=session.id,
        seq=next_seq,
        role=request.role,
        content=request.content,
    )
    db.add(msg)
    await db.flush()

    return MessageResponse(
        id=str(msg.id),
        role=msg.role,
        content=msg.content,
        created_at=msg.created_at,
    )


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(
    session_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a chat session and all its messages."""
    session = await _require_session(db, session_id, user.id)
    await db.delete(session)
    return None


# --- Helpers ---

async def _require_session(
    db: AsyncSession, session_id: uuid.UUID, user_id: uuid.UUID
) -> ChatSession:
    """Fetch session owned by user, or 404."""
    session = (
        await db.execute(
            select(ChatSession).where(
                ChatSession.id == session_id,
                ChatSession.owner_id == user_id,
            )
        )
    ).scalar_one_or_none()
    if session is None:
        raise HTTPException(status_code=404, detail="Chat session not found")
    return session
