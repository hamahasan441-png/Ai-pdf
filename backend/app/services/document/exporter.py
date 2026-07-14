"""Document exporter - fills and exports documents."""

from pathlib import Path
from typing import Any

import fitz  # PyMuPDF


class DocumentExporter:
    """Exports documents with filled form fields."""

    async def export_pdf(
        self,
        source_path: str,
        output_path: str,
        field_values: dict[str, str],
    ) -> str:
        """Export a PDF with filled form field values."""
        doc = fitz.open(source_path)

        for page in doc:
            for widget in page.widgets():
                field_name = widget.field_name
                if field_name and field_name in field_values:
                    widget.field_value = field_values[field_name]
                    widget.update()

        # Save to output path
        output = Path(output_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        doc.save(str(output))
        doc.close()

        return str(output)

    async def export_with_annotations(
        self,
        source_path: str,
        output_path: str,
        annotations: list[dict[str, Any]],
    ) -> str:
        """Export a PDF with text annotations for non-widget fields."""
        doc = fitz.open(source_path)

        for annotation in annotations:
            page_num = annotation.get("page_number", 1) - 1
            if page_num < 0 or page_num >= len(doc):
                continue

            page = doc[page_num]
            rect = fitz.Rect(annotation.get("rect", [72, 72, 200, 90]))
            value = annotation.get("value", "")

            # Insert text at the specified position
            page.insert_textbox(
                rect,
                value,
                fontsize=10,
                fontname="helv",
                color=(0, 0, 0),
            )

        output = Path(output_path)
        output.parent.mkdir(parents=True, exist_ok=True)
        doc.save(str(output))
        doc.close()

        return str(output)


document_exporter = DocumentExporter()
