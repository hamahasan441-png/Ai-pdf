"""Multimodal AI Vision Service - Understands images, scans, photos of documents.

Uses OpenRouter's free vision models:
- google/gemini-2.0-flash-exp:free (best free vision model)
- meta-llama/llama-3.2-11b-vision-instruct:free (fallback)
- google/gemma-4-26b-a4b-it:free (multimodal MoE)

Capabilities:
- Read text from images (photos of documents, receipts, IDs)
- Understand document structure from scans
- Extract form fields from images
- Detect language from any document
- Summarize complex documents
- Answer questions about document content
"""

import base64
import logging
from pathlib import Path
from typing import Any

import httpx

from app.core.config import settings
from app.core.exceptions import AIServiceError

logger = logging.getLogger(__name__)

# Vision-capable free models on OpenRouter (ordered by quality)
VISION_MODELS = [
    "google/gemini-2.0-flash-exp:free",
    "meta-llama/llama-3.2-11b-vision-instruct:free",
    "google/gemma-4-26b-a4b-it:free",
]


class VisionService:
    """AI Vision service for understanding images and scanned documents.

    Sends images as base64 to OpenRouter vision models.
    Can understand any document type: PDF pages, photos, scans, receipts, IDs.
    """

    def __init__(self):
        self.client = httpx.AsyncClient(
            base_url=settings.AI_API_BASE_URL,
            headers={
                "Authorization": f"Bearer {settings.AI_API_KEY}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://ai-pdf.app",
                "X-Title": "AI PDF Document Assistant",
            },
            timeout=120.0,
        )

    def _encode_image(self, image_path: str) -> str:
        """Read and base64-encode an image file."""
        path = Path(image_path)
        if not path.exists():
            raise AIServiceError(f"Image file not found: {image_path}")
        data = path.read_bytes()
        return base64.b64encode(data).decode("utf-8")

    def _get_mime_type(self, file_path: str) -> str:
        """Determine MIME type from file extension."""
        ext = Path(file_path).suffix.lower()
        mime_map = {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".gif": "image/gif",
            ".webp": "image/webp",
            ".tiff": "image/tiff",
            ".bmp": "image/bmp",
            ".pdf": "application/pdf",
        }
        return mime_map.get(ext, "image/png")

    async def _call_vision(
        self, image_base64: str, mime_type: str, prompt: str, system: str = ""
    ) -> str:
        """Call a vision model with an image + text prompt."""
        messages = []
        if system:
            messages.append({"role": "system", "content": system})

        messages.append({
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": f"data:{mime_type};base64,{image_base64}"
                    },
                },
                {"type": "text", "text": prompt},
            ],
        })

        # Try each vision model until one works
        last_error = None
        for model in VISION_MODELS:
            try:
                payload = {
                    "model": model,
                    "messages": messages,
                    "max_tokens": 4096,
                    "temperature": 0.2,
                }
                response = await self.client.post("/chat/completions", json=payload)
                response.raise_for_status()
                data = response.json()
                content = data["choices"][0]["message"]["content"]
                logger.info(f"Vision response from {model}: {len(content)} chars")
                return content
            except Exception as e:
                last_error = e
                logger.warning(f"Vision model {model} failed: {e}")
                continue

        raise AIServiceError(f"All vision models failed: {last_error}")

    async def understand_image(self, image_path: str) -> dict[str, Any]:
        """Fully understand an image - extract ALL information.

        Returns:
            {
                "type": "form" | "receipt" | "id_card" | "contract" | "letter" | "other",
                "language": "en",
                "summary": "...",
                "extracted_text": "...",
                "fields": [{"name": "...", "value": "...", "type": "..."}],
                "tables": [...],
                "key_information": {...}
            }
        """
        image_b64 = self._encode_image(image_path)
        mime_type = self._get_mime_type(image_path)

        prompt = """Analyze this document image completely. Extract ALL information you can see.

Return a JSON object with:
{
  "type": "form" or "receipt" or "id_card" or "contract" or "letter" or "invoice" or "certificate" or "other",
  "language": "detected language code (en, de, fr, es, ar, etc.)",
  "title": "document title if visible",
  "summary": "brief 2-3 sentence summary of what this document is",
  "extracted_text": "ALL text visible in the document, preserving structure",
  "fields": [
    {"name": "field label", "value": "field value if filled", "type": "text/date/checkbox/signature/number"}
  ],
  "tables": [
    {"headers": ["col1", "col2"], "rows": [["val1", "val2"]]}
  ],
  "key_information": {
    "names": ["any person names found"],
    "dates": ["any dates found"],
    "amounts": ["any monetary amounts"],
    "addresses": ["any addresses"],
    "identifiers": ["IDs, reference numbers, etc."]
  }
}

Be thorough - extract EVERYTHING visible. If a field is empty, include it with value as null."""

        system = "You are an expert document analyzer with OCR capabilities. You can read any document in any language. Always respond with valid JSON only. No markdown."

        response = await self._call_vision(image_b64, mime_type, prompt, system)

        # Parse JSON response
        import json
        import re
        try:
            return json.loads(response)
        except json.JSONDecodeError:
            json_match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response)
            if json_match:
                try:
                    return json.loads(json_match.group(1))
                except json.JSONDecodeError:
                    pass
            json_match = re.search(r'\{[\s\S]*\}', response)
            if json_match:
                try:
                    return json.loads(json_match.group())
                except json.JSONDecodeError:
                    pass
            # Return raw text as fallback
            return {
                "type": "other",
                "language": "en",
                "summary": "Document analyzed",
                "extracted_text": response,
                "fields": [],
                "tables": [],
                "key_information": {},
            }

    async def extract_text_from_image(self, image_path: str) -> str:
        """OCR - Extract all text from an image using AI vision."""
        image_b64 = self._encode_image(image_path)
        mime_type = self._get_mime_type(image_path)

        prompt = "Extract ALL text from this image exactly as it appears. Preserve layout, line breaks, and formatting. Include every word, number, and symbol you can see."

        return await self._call_vision(image_b64, mime_type, prompt)

    async def detect_form_fields(self, image_path: str) -> list[dict[str, Any]]:
        """Detect all form fields in a document image.

        Returns list of fields with positions and values.
        """
        image_b64 = self._encode_image(image_path)
        mime_type = self._get_mime_type(image_path)

        prompt = """Detect ALL form fields in this document image.

Return JSON:
{
  "fields": [
    {
      "label": "the field label/name",
      "value": "current value if filled, null if empty",
      "type": "text|date|email|phone|checkbox|radio|signature|number|address",
      "required": true/false,
      "position": "top-left|top-right|middle-left|middle-right|bottom-left|bottom-right"
    }
  ]
}

Include EVERY field you can see, even empty ones."""

        system = "You are a form detection expert. Respond with valid JSON only."
        response = await self._call_vision(image_b64, mime_type, prompt, system)

        import json
        import re
        try:
            data = json.loads(response)
            return data.get("fields", [])
        except json.JSONDecodeError:
            json_match = re.search(r'\{[\s\S]*\}', response)
            if json_match:
                try:
                    data = json.loads(json_match.group())
                    return data.get("fields", [])
                except json.JSONDecodeError:
                    pass
            return []

    async def answer_question(self, image_path: str, question: str) -> str:
        """Answer any question about a document image."""
        image_b64 = self._encode_image(image_path)
        mime_type = self._get_mime_type(image_path)
        return await self._call_vision(image_b64, mime_type, question)

    async def summarize_document(self, image_path: str, language: str = "en") -> str:
        """Get a comprehensive summary of a document image."""
        image_b64 = self._encode_image(image_path)
        mime_type = self._get_mime_type(image_path)

        prompt = f"Provide a comprehensive summary of this document in {language}. Include: what type of document it is, who it's from/to, key dates, amounts, and all important information."

        return await self._call_vision(image_b64, mime_type, prompt)

    async def translate_document(self, image_path: str, target_language: str) -> str:
        """Translate all text in a document image to target language."""
        image_b64 = self._encode_image(image_path)
        mime_type = self._get_mime_type(image_path)

        prompt = f"Translate ALL text in this document to {target_language}. Preserve the original structure and formatting. Translate every word, label, and piece of text you can see."

        return await self._call_vision(image_b64, mime_type, prompt)

    async def close(self):
        await self.client.aclose()


# Singleton
vision_service = VisionService()
