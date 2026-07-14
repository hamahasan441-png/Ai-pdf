"""Document parser for PDF and DOCX files."""

from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import fitz  # PyMuPDF
from docx import Document as DocxDocument
from pypdf import PdfReader


@dataclass
class ParsedPage:
    """Represents a parsed page from a document."""

    page_number: int
    text: str
    images: list[bytes] = field(default_factory=list)


@dataclass
class ParsedDocument:
    """Represents a fully parsed document."""

    pages: list[ParsedPage]
    page_count: int
    full_text: str
    metadata: dict = field(default_factory=dict)
    form_fields: list[dict] = field(default_factory=list)


class DocumentParser:
    """Parses PDF and DOCX documents, extracting text and form fields."""

    async def parse(self, file_path: str, mime_type: str) -> ParsedDocument:
        """Parse a document based on its mime type."""
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"Document not found: {file_path}")

        if mime_type == "application/pdf":
            return await self._parse_pdf(path)
        elif "wordprocessingml" in mime_type:
            return await self._parse_docx(path)
        else:
            raise ValueError(f"Unsupported mime type: {mime_type}")

    async def _parse_pdf(self, path: Path) -> ParsedDocument:
        """Parse a PDF file using PyMuPDF and extract form fields."""
        doc = fitz.open(str(path))
        pages: list[ParsedPage] = []
        form_fields: list[dict] = []

        for page_num in range(len(doc)):
            page = doc[page_num]
            text = page.get_text()
            pages.append(ParsedPage(page_number=page_num + 1, text=text))

            # Extract form widgets (interactive form fields)
            for widget in page.widgets():
                form_fields.append({
                    "field_name": widget.field_name or f"field_{page_num}_{len(form_fields)}",
                    "field_label": widget.field_label or widget.field_name,
                    "field_type": self._map_widget_type(widget.field_type),
                    "page_number": page_num + 1,
                    "rect": list(widget.rect),
                    "value": widget.field_value,
                })

        doc.close()
        full_text = "\n\n".join(p.text for p in pages)

        # Also try pypdf for additional form field detection
        try:
            reader = PdfReader(str(path))
            metadata = {
                "title": reader.metadata.title if reader.metadata else None,
                "author": reader.metadata.author if reader.metadata else None,
            }
        except Exception:
            metadata = {}

        return ParsedDocument(
            pages=pages,
            page_count=len(pages),
            full_text=full_text,
            metadata=metadata,
            form_fields=form_fields,
        )

    async def _parse_docx(self, path: Path) -> ParsedDocument:
        """Parse a DOCX file."""
        doc = DocxDocument(str(path))
        full_text = "\n".join(paragraph.text for paragraph in doc.paragraphs)
        pages = [ParsedPage(page_number=1, text=full_text)]

        metadata = {
            "title": doc.core_properties.title,
            "author": doc.core_properties.author,
        }

        return ParsedDocument(
            pages=pages,
            page_count=1,
            full_text=full_text,
            metadata=metadata,
            form_fields=[],
        )

    @staticmethod
    def _map_widget_type(widget_type: int) -> str:
        """Map PyMuPDF widget type to our field type."""
        type_map = {
            1: "text",
            2: "checkbox",
            3: "radio",
            4: "select",
            5: "text",  # multiline
            6: "signature",
        }
        return type_map.get(widget_type, "text")


document_parser = DocumentParser()
