"""Document Understanding Service - Makes the AI understand ANY data.

This is the brain of the app. It takes any input and makes sense of it:
- PDF text → AI understands content, detects fields, classifies document
- Image → AI vision reads it, extracts all data
- DOCX text → AI analyzes structure
- Scanned PDF → Converts pages to images → AI vision reads them

The goal: user gives ANY document, AI understands EVERYTHING about it.
"""

import logging
import tempfile
from pathlib import Path
from typing import Any

import fitz  # PyMuPDF for PDF→Image conversion

from app.services.ai.provider import ai_provider
from app.services.ai.vision import vision_service

logger = logging.getLogger(__name__)

# Comprehensive document analysis prompt
DOCUMENT_ANALYSIS_PROMPT = """Analyze this document text thoroughly. Identify:
1. Document type (form, contract, invoice, letter, certificate, ID, receipt, etc.)
2. Language
3. All form fields (with labels, values, types)
4. Key entities (names, dates, amounts, addresses, IDs)
5. Logical structure (sections, tables)
6. Any action items or requirements

Return JSON:
{
  "document_type": "...",
  "language": "...",
  "title": "...",
  "summary": "2-3 sentence summary",
  "confidence": 0.0-1.0,
  "form_fields": [
    {"label": "...", "value": "..." or null, "type": "text|date|email|phone|number|checkbox", "required": true/false}
  ],
  "key_entities": {
    "people": ["names"],
    "organizations": ["org names"],
    "dates": ["dates found"],
    "amounts": ["monetary values"],
    "addresses": ["addresses"],
    "reference_numbers": ["IDs, case numbers, etc."]
  },
  "sections": ["list of document sections/headings"],
  "action_items": ["things that need to be done based on this document"],
  "needs_ocr": false
}"""


class DocumentUnderstandingService:
    """Makes AI understand any document - the core intelligence of the app."""

    async def understand(self, file_path: str, mime_type: str) -> dict[str, Any]:
        """Understand ANY document. Routes to the best method based on type.

        Args:
            file_path: Path to the uploaded file
            mime_type: MIME type of the file

        Returns:
            Complete understanding of the document (type, fields, entities, summary)
        """
        logger.info(f"Understanding document: {file_path} ({mime_type})")

        if mime_type in ("image/png", "image/jpeg", "image/jpg", "image/tiff", "image/webp", "image/gif"):
            # Direct image → AI Vision
            return await self._understand_image(file_path)
        elif mime_type == "application/pdf":
            # PDF → try text extraction first, fallback to vision
            return await self._understand_pdf(file_path)
        elif "wordprocessingml" in mime_type or mime_type == "application/msword":
            # DOCX → extract text → AI analysis
            return await self._understand_docx(file_path)
        else:
            # Unknown → try as image
            return await self._understand_image(file_path)

    async def _understand_image(self, file_path: str) -> dict[str, Any]:
        """Understand a document image using AI vision."""
        logger.info("Using AI Vision to understand image")
        result = await vision_service.understand_image(file_path)
        result["method"] = "vision"
        result["needs_ocr"] = False  # Vision IS the OCR
        return result

    async def _understand_pdf(self, file_path: str) -> dict[str, Any]:
        """Understand a PDF - tries text first, falls back to vision for scans."""
        doc = fitz.open(file_path)
        all_text = ""
        is_scanned = True
        page_count = len(doc)

        # Extract text from all pages
        for page_num in range(page_count):
            page = doc[page_num]
            text = page.get_text()
            all_text += text + "\n"
            # If we get meaningful text, it's not a pure scan
            if len(text.strip()) > 50:
                is_scanned = False

        # Extract form widgets
        form_fields = []
        for page_num in range(page_count):
            page = doc[page_num]
            for widget in page.widgets():
                form_fields.append({
                    "label": widget.field_label or widget.field_name or f"field_{page_num}",
                    "value": widget.field_value,
                    "type": "text",
                    "page": page_num + 1,
                })

        doc.close()

        if is_scanned:
            # Scanned PDF → convert first page to image → use AI Vision
            logger.info("PDF appears scanned, using AI Vision")
            image_path = await self._pdf_page_to_image(file_path, page=0)
            try:
                result = await vision_service.understand_image(image_path)
                result["method"] = "vision"
                result["page_count"] = page_count
                result["needs_ocr"] = False
                return result
            finally:
                Path(image_path).unlink(missing_ok=True)
        else:
            # Has text → use text-based AI analysis
            logger.info(f"PDF has text ({len(all_text)} chars), using text AI")
            result = await self._analyze_text(all_text[:12000])
            result["method"] = "text"
            result["page_count"] = page_count
            result["extracted_text"] = all_text[:5000]

            # Add any interactive form fields found
            if form_fields:
                existing_fields = result.get("form_fields", [])
                for f in form_fields:
                    existing_fields.append(f)
                result["form_fields"] = existing_fields

            return result

    async def _understand_docx(self, file_path: str) -> dict[str, Any]:
        """Understand a DOCX file by extracting text and analyzing."""
        from docx import Document as DocxDocument

        doc = DocxDocument(file_path)
        paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
        full_text = "\n".join(paragraphs)

        # Also extract tables
        tables_text = ""
        for table in doc.tables:
            for row in table.rows:
                row_text = " | ".join(cell.text for cell in row.cells)
                tables_text += row_text + "\n"

        combined_text = full_text + "\n\n" + tables_text

        result = await self._analyze_text(combined_text[:12000])
        result["method"] = "text"
        result["page_count"] = 1
        result["extracted_text"] = combined_text[:5000]
        return result

    async def _analyze_text(self, text: str) -> dict[str, Any]:
        """Analyze document text using AI (non-vision, text-only model)."""

        messages = [
            {"role": "system", "content": DOCUMENT_ANALYSIS_PROMPT},
            {"role": "user", "content": f"Analyze this document:\n\n{text}"},
        ]

        try:
            result = await ai_provider.chat_completion_json(
                messages=messages,
                use_advanced=True,
                max_tokens=4096,
            )
            return result
        except Exception as e:
            logger.error(f"Text analysis failed: {e}")
            return {
                "document_type": "unknown",
                "language": "en",
                "title": "Document",
                "summary": "Could not fully analyze this document.",
                "form_fields": [],
                "key_entities": {},
                "sections": [],
                "action_items": [],
            }

    async def _pdf_page_to_image(self, pdf_path: str, page: int = 0) -> str:
        """Convert a PDF page to a PNG image for vision analysis."""
        doc = fitz.open(pdf_path)
        pdf_page = doc[page]

        # Render at 2x resolution for better readability
        zoom = 2.0
        mat = fitz.Matrix(zoom, zoom)
        pixmap = pdf_page.get_pixmap(matrix=mat)

        # Save to temp file
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        pixmap.save(tmp.name)
        doc.close()

        return tmp.name

    async def ask_about_document(
        self, file_path: str, mime_type: str, question: str
    ) -> str:
        """Ask any question about a document.

        User can ask: "What is the total amount?", "Who signed this?",
        "What is the deadline?", "Translate to Arabic", etc.
        """
        if mime_type in ("image/png", "image/jpeg", "image/jpg", "image/tiff", "image/webp"):
            return await vision_service.answer_question(file_path, question)
        elif mime_type == "application/pdf":
            # Convert first page to image for visual Q&A
            image_path = await self._pdf_page_to_image(file_path)
            try:
                return await vision_service.answer_question(image_path, question)
            finally:
                Path(image_path).unlink(missing_ok=True)
        else:
            # Text-based Q&A
            from docx import Document as DocxDocument
            doc = DocxDocument(file_path)
            text = "\n".join(p.text for p in doc.paragraphs)

            messages = [
                {"role": "system", "content": "Answer the user's question about this document accurately and concisely."},
                {"role": "user", "content": f"Document:\n{text[:6000]}\n\nQuestion: {question}"},
            ]
            return await ai_provider.chat_completion(messages=messages)


# Singleton
understanding_service = DocumentUnderstandingService()
