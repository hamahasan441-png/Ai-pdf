"""Document management endpoints."""

import logging
import uuid
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, File, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user, get_optional_user
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

logger = logging.getLogger(__name__)

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
    """Run the full AI document processing pipeline.

    Pipeline stages:
    1. Virus scan (malware detection)
    2. File validation (type, corruption)
    3. Document type detection
    4. Parsing (text extraction / AI vision for images)
    5. OCR (for scanned documents)
    6. Layout analysis
    7. Field detection (forms, tables, checkboxes)
    8. Semantic field mapping (multi-language)
    9. Profile mapping + auto-fill
    10. Validation
    11. Ready to export

    Returns full pipeline result with all extracted data.
    """
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.owner_id == current_user.id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    document.status = DocumentStatus.PROCESSING
    await db.flush()

    # Get user profile for auto-fill
    profile_data = None
    try:
        from app.services.profile.profile_service import ProfileService
        profile_svc = ProfileService(db)
        profile_data = await profile_svc.get_profile_data_for_filling(current_user.id)
    except Exception:
        pass  # Profile is optional

    # Run the full pipeline
    from app.services.pipeline.orchestrator import pipeline

    pipeline_result = await pipeline.process(
        file_path=document.file_path,
        mime_type=document.mime_type,
        profile_data=profile_data,
    )

    # Update document with results
    if pipeline_result.success:
        document.status = DocumentStatus.ANALYZED
        document.ai_summary = pipeline_result.summary
        document.language = pipeline_result.language
        document.page_count = pipeline_result.page_count
        document.document_category = pipeline_result.document_type
        document.extracted_text = pipeline_result.text_content

        # Store detected form fields
        if pipeline_result.fields:
            from app.models.document import FormField
            for f in pipeline_result.fields:
                # Find auto-filled value if available
                filled_value = None
                for ff in pipeline_result.filled_fields:
                    if ff.get("field_name") == (f.get("label") or f.get("name", "")):
                        filled_value = ff.get("value")
                        break

                db.add(FormField(
                    document_id=document.id,
                    field_name=f.get("label") or f.get("name", "unknown"),
                    field_label=f.get("label") or f.get("name", ""),
                    field_type=f.get("type", "text"),
                    suggested_value=filled_value or f.get("value"),
                    confidence_score=f.get("mapping_confidence", 0.8),
                ))
    else:
        document.status = DocumentStatus.ERROR

    await db.flush()

    return {
        "status": pipeline_result.stage.value,
        "success": pipeline_result.success,
        "document_id": str(document_id),
        "document_type": pipeline_result.document_type,
        "language": pipeline_result.language,
        "page_count": pipeline_result.page_count,
        "summary": pipeline_result.summary,
        "fields_detected": len(pipeline_result.fields),
        "fields_filled": len(pipeline_result.filled_fields),
        "tables_detected": len(pipeline_result.tables),
        "entities": pipeline_result.entities,
        "validation_issues": pipeline_result.validation_issues,
        "stages_completed": pipeline_result.stages_completed,
        "processing_time_ms": pipeline_result.processing_time_ms,
        "error": pipeline_result.error,
    }


@router.post("/{document_id}/ask")
async def ask_document(
    document_id: uuid.UUID,
    question: str = "",
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Ask any question about a document using AI.
    
    Examples:
    - "What is the total amount?"
    - "Who signed this document?"
    - "What is the deadline?"
    - "Summarize this in Arabic"
    - "What fields are empty?"
    - "Is this document valid?"
    """
    result = await db.execute(
        select(Document).where(
            Document.id == document_id,
            Document.owner_id == current_user.id,
        )
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    if not question:
        from app.core.exceptions import ValidationError
        raise ValidationError("Please provide a question")

    from app.services.ai.understanding import understanding_service

    answer = await understanding_service.ask_about_document(
        file_path=document.file_path,
        mime_type=document.mime_type,
        question=question,
    )

    return {
        "document_id": str(document_id),
        "question": question,
        "answer": answer,
    }


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



# ============================================================
# GUEST ENDPOINTS - Work without authentication
# ============================================================

@router.post("/guest/upload", response_model=DocumentUploadResponse, status_code=201)
async def guest_upload_document(
    file: UploadFile = File(...),
    current_user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload a document as a guest (no login required).

    Guest uploads are stored temporarily and processed the same way
    as authenticated uploads. Guest documents are deleted after 24h.

    If user is logged in, document is linked to their account.
    """
    content = await file.read()
    file_size = len(content)
    if file_size > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
        raise FileSizeLimitError(settings.MAX_UPLOAD_SIZE_MB)

    mime_type = file.content_type or "application/octet-stream"
    doc_type = MIME_TYPE_MAP.get(mime_type)
    if doc_type is None:
        from app.core.exceptions import ValidationError
        raise ValidationError(f"Unsupported file type: {mime_type}")

    file_id = uuid.uuid4()
    owner_id = current_user.id if current_user else uuid.uuid4()
    upload_dir = Path(settings.UPLOAD_DIR) / "guest" / str(owner_id)
    upload_dir.mkdir(parents=True, exist_ok=True)
    file_path = upload_dir / f"{file_id}_{file.filename}"
    file_path.write_bytes(content)

    document = Document(
        id=file_id,
        owner_id=owner_id,
        filename=f"{file_id}_{file.filename}",
        original_filename=file.filename,
        file_path=str(file_path),
        file_size=file_size,
        mime_type=mime_type,
        document_type=doc_type,
        status=DocumentStatus.UPLOADED,
        is_guest=True,
    )
    db.add(document)
    await db.flush()

    return document


@router.post("/guest/{document_id}/analyze")
async def guest_analyze_document(
    document_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    """Analyze a guest document using the full AI pipeline.

    No login required. Same AI power as authenticated users.
    Guest limit: 3 analyses per hour per IP.
    """
    result = await db.execute(
        select(Document).where(Document.id == document_id)
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    document.status = DocumentStatus.PROCESSING
    await db.flush()

    from app.services.pipeline.orchestrator import pipeline

    pipeline_result = await pipeline.process(
        file_path=document.file_path,
        mime_type=document.mime_type,
        profile_data=None,  # No profile for guests
    )

    if pipeline_result.success:
        document.status = DocumentStatus.ANALYZED
        document.ai_summary = pipeline_result.summary
        document.language = pipeline_result.language
        document.page_count = pipeline_result.page_count
        document.document_category = pipeline_result.document_type
        document.extracted_text = pipeline_result.text_content

        if pipeline_result.fields:
            from app.models.document import FormField
            for f in pipeline_result.fields:
                db.add(FormField(
                    document_id=document.id,
                    field_name=f.get("label") or f.get("name", "unknown"),
                    field_label=f.get("label") or f.get("name", ""),
                    field_type=f.get("type", "text"),
                    suggested_value=f.get("value"),
                    confidence_score=f.get("mapping_confidence", 0.8),
                ))
    else:
        document.status = DocumentStatus.ERROR

    await db.flush()

    return {
        "status": pipeline_result.stage.value,
        "success": pipeline_result.success,
        "document_id": str(document_id),
        "document_type": pipeline_result.document_type,
        "language": pipeline_result.language,
        "summary": pipeline_result.summary,
        "fields_detected": len(pipeline_result.fields),
        "stages_completed": pipeline_result.stages_completed,
        "processing_time_ms": pipeline_result.processing_time_ms,
        "guest_mode": True,
        "upgrade_hint": "Sign up free to save documents and auto-fill forms from your profile",
    }


@router.get("/guest/{document_id}")
async def guest_get_document(
    document_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    """Get a guest document's details and analysis results."""
    result = await db.execute(
        select(Document).where(Document.id == document_id)
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    return document


@router.post("/guest/{document_id}/ask")
async def guest_ask_document(
    document_id: uuid.UUID,
    question: str = "",
    db: AsyncSession = Depends(get_db),
):
    """Ask a question about a guest document."""
    result = await db.execute(
        select(Document).where(Document.id == document_id)
    )
    document = result.scalar_one_or_none()
    if not document:
        raise NotFoundError("Document")

    if not question:
        from app.core.exceptions import ValidationError
        raise ValidationError("Please provide a question")

    from app.services.ai.understanding import understanding_service

    answer = await understanding_service.ask_about_document(
        file_path=document.file_path,
        mime_type=document.mime_type,
        question=question,
    )

    return {
        "document_id": str(document_id),
        "question": question,
        "answer": answer,
        "guest_mode": True,
    }
