"""Semantic field mapper - maps form fields to user profile data."""

from typing import Optional

from app.services.ai.provider import ai_provider

FIELD_MAPPING_PROMPT = """You are a form field mapping assistant. Given a list of form fields detected in a document, map each field to the corresponding user profile data field.

Profile fields available:
- first_name, last_name, phone, address, city, state, zip_code, country, date_of_birth, ssn

For each form field, return a JSON object with the mapping. If a field doesn't map to any profile field, set mapping to null.

Respond with JSON format:
{
  "mappings": [
    {"field_name": "...", "profile_field": "..." or null, "confidence": 0.0-1.0}
  ]
}"""


class FieldMapper:
    """Maps document form fields to user profile fields using AI."""

    async def map_fields(
        self, form_fields: list[dict[str, str]]
    ) -> list[dict[str, Optional[str]]]:
        """Map form fields to profile fields using semantic understanding."""
        if not form_fields:
            return []

        fields_description = "\n".join(
            f"- {f.get('field_name', '')}: label='{f.get('field_label', '')}', type={f.get('field_type', 'text')}"
            for f in form_fields
        )

        messages = [
            {"role": "system", "content": FIELD_MAPPING_PROMPT},
            {
                "role": "user",
                "content": f"Map these form fields:\n{fields_description}",
            },
        ]

        result = await ai_provider.chat_completion_json(messages)
        return result.get("mappings", [])


field_mapper = FieldMapper()
