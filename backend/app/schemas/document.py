"""Document request/response schemas."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class DocumentUploadResponse(BaseModel):
    """Response after uploading a document."""

    id: str
    filename: str
    original_filename: str
    file_size: int
    document_type: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class DocumentResponse(BaseModel):
    """Full document response."""

    id: str
    filename: str
    original_filename: str
    file_size: int
    mime_type: str
    document_type: str
    status: str
    page_count: Optional[int] = None
    ai_summary: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    form_fields: list["FormFieldResponse"] = []

    class Config:
        from_attributes = True


class FormFieldResponse(BaseModel):
    """Form field response."""

    id: str
    field_name: str
    field_label: Optional[str] = None
    field_type: str
    page_number: int
    suggested_value: Optional[str] = None
    confirmed_value: Optional[str] = None
    confidence_score: Optional[float] = None
    profile_field_mapping: Optional[str] = None

    class Config:
        from_attributes = True


class FormFieldUpdateRequest(BaseModel):
    """Update a form field value."""

    confirmed_value: str


class BulkFormFieldUpdate(BaseModel):
    """Bulk update form field values."""

    fields: list[dict] = Field(
        ..., description="List of {field_id: str, confirmed_value: str}"
    )


class DocumentListResponse(BaseModel):
    """Paginated document list response."""

    documents: list[DocumentUploadResponse]
    total: int
    page: int
    per_page: int


class DocumentAnalysisRequest(BaseModel):
    """Request to trigger AI analysis on a document."""

    analyze_forms: bool = True
    auto_fill: bool = True


class ExportRequest(BaseModel):
    """Document export request."""

    format: str = Field(default="pdf", description="Export format: pdf, docx")
    include_filled_values: bool = True
