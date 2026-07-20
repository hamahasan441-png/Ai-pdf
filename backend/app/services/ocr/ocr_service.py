"""OCR service for extracting text from scanned documents and images."""

from pathlib import Path

import fitz  # PyMuPDF

from app.services.ai.provider import ai_provider

OCR_PROMPT = """Analyze this image and extract all visible text. 
Identify any form fields, labels, and their positions.
Return the result as JSON:
{
  "extracted_text": "full text content",
  "form_fields": [
    {"label": "...", "field_type": "text|checkbox|date|...", "value": "..." or null}
  ]
}"""


class OCRService:
    """OCR service using AI vision capabilities for scanned documents."""

    async def extract_text_from_image(self, image_path: str) -> dict:
        """Extract text from an image file using AI vision."""
        import base64

        path = Path(image_path)
        if not path.exists():
            raise FileNotFoundError(f"Image not found: {image_path}")

        # Read and encode the image
        with open(path, "rb") as f:
            image_data = base64.b64encode(f.read()).decode()

        # Determine mime type
        suffix = path.suffix.lower()
        mime_map = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
        mime_type = mime_map.get(suffix, "image/png")

        messages = [
            {"role": "system", "content": OCR_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Extract all text and form fields from this document image."},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:{mime_type};base64,{image_data}"},
                    },
                ],
            },
        ]

        result = await ai_provider.chat_completion_json(messages, max_tokens=4096)
        return result

    async def extract_text_from_pdf_page(
        self, pdf_path: str, page_number: int
    ) -> dict:
        """Extract text from a specific PDF page rendered as an image."""
        doc = fitz.open(pdf_path)
        if page_number < 1 or page_number > len(doc):
            doc.close()
            raise ValueError(f"Invalid page number: {page_number}")

        page = doc[page_number - 1]

        # Render page to image at 300 DPI
        pix = page.get_pixmap(dpi=300)
        import base64
        image_data = base64.b64encode(pix.tobytes("png")).decode()
        doc.close()

        messages = [
            {"role": "system", "content": OCR_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": f"Extract text from page {page_number}."},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{image_data}"},
                    },
                ],
            },
        ]

        result = await ai_provider.chat_completion_json(messages, max_tokens=4096)
        return result


ocr_service = OCRService()
