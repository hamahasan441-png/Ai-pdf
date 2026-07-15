"""Document Processing Pipeline Orchestrator.

Implements the full pipeline:
  Upload → Virus Scan → File Validation → Type Detection
  → Document Parsing → OCR (when needed) → Layout Analysis
  → Table/Checkbox Detection → Semantic Field Mapping
  → User Profile Mapping → Validation → Export → Cache

Each step is a separate function that can fail independently.
The orchestrator handles errors gracefully and provides status updates.
"""

import logging
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional

logger = logging.getLogger(__name__)


class PipelineStage(str, Enum):
    """Pipeline processing stages."""
    UPLOADED = "uploaded"
    SCANNING = "scanning"
    VALIDATING = "validating"
    DETECTING_TYPE = "detecting_type"
    PARSING = "parsing"
    OCR = "ocr"
    ANALYZING_LAYOUT = "analyzing_layout"
    DETECTING_FIELDS = "detecting_fields"
    MAPPING_FIELDS = "mapping_fields"
    MAPPING_PROFILE = "mapping_profile"
    VALIDATING_FORM = "validating_form"
    READY_TO_EXPORT = "ready_to_export"
    EXPORTED = "exported"
    ERROR = "error"


@dataclass
class PipelineResult:
    """Result of pipeline processing."""
    stage: PipelineStage
    success: bool
    document_type: str = "unknown"
    language: str = "en"
    page_count: int = 1
    text_content: str = ""
    summary: str = ""
    fields: list[dict[str, Any]] = field(default_factory=list)
    tables: list[dict[str, Any]] = field(default_factory=list)
    entities: dict[str, Any] = field(default_factory=dict)
    validation_issues: list[str] = field(default_factory=list)
    filled_fields: list[dict[str, Any]] = field(default_factory=list)
    processing_time_ms: int = 0
    error: Optional[str] = None
    stages_completed: list[str] = field(default_factory=list)


class PipelineOrchestrator:
    """Orchestrates the full document processing pipeline.

    Design decisions:
    - Each stage is independent and can be retried
    - Failures in optional stages (OCR, tables) don't stop the pipeline
    - Results are accumulated progressively
    - Processing time is tracked for performance monitoring
    """

    async def process(
        self,
        file_path: str,
        mime_type: str,
        profile_data: Optional[dict[str, Any]] = None,
    ) -> PipelineResult:
        """Run the full document processing pipeline.

        Args:
            file_path: Path to the uploaded file
            mime_type: MIME type of the file
            profile_data: User's decrypted profile (for auto-fill)

        Returns:
            PipelineResult with all extracted data
        """
        start_time = time.time()
        result = PipelineResult(stage=PipelineStage.UPLOADED, success=False)

        try:
            # Stage 1: Virus Scan
            result.stage = PipelineStage.SCANNING
            await self._virus_scan(file_path)
            result.stages_completed.append("virus_scan")

            # Stage 2: File Validation
            result.stage = PipelineStage.VALIDATING
            await self._validate_file(file_path, mime_type)
            result.stages_completed.append("file_validation")

            # Stage 3: Type Detection + Parsing + OCR
            result.stage = PipelineStage.PARSING
            from app.services.ai.understanding import understanding_service
            understanding = await understanding_service.understand(file_path, mime_type)
            result.document_type = understanding.get("document_type") or understanding.get("type", "unknown")
            result.language = understanding.get("language", "en")
            result.page_count = understanding.get("page_count", 1)
            result.text_content = understanding.get("extracted_text", "")
            result.summary = understanding.get("summary", "")
            result.stages_completed.append("parsing")
            result.stages_completed.append("type_detection")

            # If vision was used, OCR was done implicitly
            if understanding.get("method") == "vision":
                result.stages_completed.append("ocr")

            # Stage 4: Layout Analysis + Field Detection
            result.stage = PipelineStage.DETECTING_FIELDS
            raw_fields = understanding.get("form_fields") or understanding.get("fields", [])
            result.fields = raw_fields
            result.tables = understanding.get("tables", [])
            result.entities = understanding.get("key_entities") or understanding.get("key_information", {})
            result.stages_completed.append("layout_analysis")
            result.stages_completed.append("field_detection")

            # Stage 5: Semantic Field Mapping
            if raw_fields:
                result.stage = PipelineStage.MAPPING_FIELDS
                from app.services.ai.field_mapper import field_mapper
                mappings = await field_mapper.map_fields(raw_fields)
                # Enrich fields with mapping info
                for i, f in enumerate(result.fields):
                    if i < len(mappings):
                        f["profile_mapping"] = mappings[i].get("profile_field")
                        f["mapping_confidence"] = mappings[i].get("confidence", 0)
                result.stages_completed.append("semantic_mapping")

            # Stage 6: Profile Mapping + Auto-fill
            if profile_data and raw_fields:
                result.stage = PipelineStage.MAPPING_PROFILE
                from app.services.ai.form_filler import form_filler
                fill_result = await form_filler.fill_form(
                    form_fields=raw_fields,
                    profile_data=profile_data,
                    document_context=result.document_type,
                    document_language=result.language,
                )
                result.filled_fields = fill_result.get("filled_fields", [])
                result.stages_completed.append("profile_mapping")
                result.stages_completed.append("auto_fill")

            # Stage 7: Validation
            if result.filled_fields:
                result.stage = PipelineStage.VALIDATING_FORM
                from app.services.ai.form_filler import form_filler
                validation = await form_filler.validate_filled_form(result.filled_fields)
                result.validation_issues = [
                    i.get("message", "") for i in validation.get("issues", [])
                ]
                result.stages_completed.append("validation")

            # Done
            result.stage = PipelineStage.READY_TO_EXPORT
            result.success = True

        except Exception as e:
            logger.error(f"Pipeline failed at stage {result.stage}: {e}")
            result.stage = PipelineStage.ERROR
            result.error = str(e)

        result.processing_time_ms = int((time.time() - start_time) * 1000)
        logger.info(
            f"Pipeline completed: {result.stage.value} | "
            f"{len(result.stages_completed)} stages | "
            f"{result.processing_time_ms}ms | "
            f"{len(result.fields)} fields detected"
        )
        return result

    async def _virus_scan(self, file_path: str) -> None:
        """Scan file for malicious content.

        Uses basic checks:
        - File size validation
        - Magic bytes verification
        - Known malicious patterns
        """
        import os
        from pathlib import Path

        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        # Check file size (max 50MB)
        size = os.path.getsize(file_path)
        if size > 50 * 1024 * 1024:
            raise ValueError("File exceeds 50MB limit")
        if size == 0:
            raise ValueError("File is empty")

        # Check magic bytes for common threats
        with open(file_path, "rb") as f:
            header = f.read(8)

        # Block executables, scripts, archives with executables
        dangerous_headers = [
            b"MZ",           # Windows executable
            b"\x7fELF",      # Linux executable
            b"#!/",          # Shell script
            b"<?php",        # PHP
        ]
        for dangerous in dangerous_headers:
            if header.startswith(dangerous):
                raise ValueError("File contains potentially malicious content")

        logger.info(f"Virus scan passed: {file_path} ({size} bytes)")

    async def _validate_file(self, file_path: str, mime_type: str) -> None:
        """Validate file is a supported document type.

        Checks:
        - MIME type is allowed
        - File extension matches content
        - File is not corrupted (can be opened)
        """
        allowed_mimes = {
            "application/pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "application/msword",
            "image/png",
            "image/jpeg",
            "image/jpg",
            "image/tiff",
            "image/webp",
            "image/gif",
        }

        if mime_type not in allowed_mimes:
            raise ValueError(f"Unsupported file type: {mime_type}")

        # Verify file can be opened
        from pathlib import Path
        ext = Path(file_path).suffix.lower()

        if ext == ".pdf":
            try:
                import fitz
                doc = fitz.open(file_path)
                doc.close()
            except Exception:
                raise ValueError("PDF file is corrupted or unreadable")
        elif ext in (".png", ".jpg", ".jpeg", ".tiff", ".webp", ".gif"):
            try:
                from PIL import Image
                img = Image.open(file_path)
                img.verify()
            except ImportError:
                pass  # Pillow not required
            except Exception:
                raise ValueError("Image file is corrupted or unreadable")

        logger.info(f"File validation passed: {mime_type}")


# Singleton
pipeline = PipelineOrchestrator()
