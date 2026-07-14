"""Document management endpoints."""

import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.core.config import settings
from app.core.exceptions import FileSizeLimitError, NotFoundError
from app.db.database import get_db
from app.models.document import Document, DocumentStatus, DocumentType
from app.models.user import User
from app.schemas.document import (
    DocumentAnalysisRequest,
    DocumentListResponse,
    DocumentResponse,
    DocumentUploadResponse,
    ExportRequest,
)

router = APIRouter()

MIME_TYPE_MAP = {
    "application/pdf": DocumentType.PDF,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": DocumentType.DOCX,
    "image/png": DocumentType.IMAGE,
    "image/jpeg": DocumentType.IMAGE,
}


@router.post("/upload", response_model=DocumentUploadResponse, status_code=201)
async def upload_document(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload a document for processing."""
    # Validate file size
    content = await file.read()
    file_size = len(content)
    if file_size > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
        raise FileSizeLimitError(settings.MAX_UPLOAD_SIZE_MB)

    # Determine document type
    mime_type = file.content_type or "application/octet-stream"
    doc_type = MIME_TYPE_MAP.get(mime_type)
    if doc_type is None:
        from app.core.exceptions import ValidationError
        raise ValidationError(f"Unsupported file type: {mime_type}")

    # Save file to disk
    file_id = uuid.uuid4()
    upload_dir = Path(settings.UPLOAD_DIR) / str(current_user.id)
    upload_dir.mkdir(parents=True, exist_ok=True)
    file_path = upload_dir / f"{file_id}_{file.filename}"
    file_path.write_bytes(content)

    # Create database record
    document = Document(
        id=file_id,
        owner_id=current_user.id,
        filename=f"{file_id}_{file.filename}",
        original_filename=file.filename,
        file_path=str(file_path),
        file_size=file_size,
        mime_type=mime_type,
        document_type=doc_type,
        status=DocumentStatus.UPLOADED,
    )
    db.add(document)
    await db.flush()

    return document


@router.get("/", response_model=DocumentListResponse)
async def list_documents(
    page: int = 1,
    per_page: int = 20,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List user's documents with pagination."""
    offset = (page - 1) * per_page
    query = (
        select(Document)
        .where(Document.owner_id == current_user.id)
        .order_by(Document.created_at.desc())
        .offset(offset)
        .limit(per_page)
    )
    result = await db.execute(query)
    documents = result.scalars().all()

    # Count total
    from sqlalchemy import func
    count_query = select(func.count()).where(Document.owner_id == current_user.id)
    total = (await db.execute(count_query)).scalar() or 0

    return DocumentListResponse(
        documents=documents,
        total=total,
        page=page,
        per_page=per_page,
    )


@router.get("/{document_id}", response_model=DocumentResponse)
async def get_document(
    document_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get document details including form fields."""
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.owner_id == current_user.id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")
    return document


@router.post("/{document_id}/analyze")
async def analyze_document(
    document_id: uuid.UUID,
    request: DocumentAnalysisRequest = DocumentAnalysisRequest(),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Trigger AI analysis on an uploaded document."""
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.owner_id == current_user.id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    # TODO: Trigger async processing pipeline
    document.status = DocumentStatus.PROCESSING
    await db.flush()

    return {"status": "processing", "document_id": str(document_id)}


@router.delete("/{document_id}", status_code=204)
async def delete_document(
    document_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a document."""
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.owner_id == current_user.id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    # Delete file from disk
    file_path = Path(document.file_path)
    if file_path.exists():
        file_path.unlink()

    await db.delete(document)
