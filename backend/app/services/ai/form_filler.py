"""AI-powered form filler service."""

from typing import Any

from app.services.ai.field_mapper import field_mapper
from app.services.ai.provider import ai_provider

FORM_FILL_PROMPT = """You are an intelligent form-filling assistant. Given a user's profile data and a list of form fields with their mappings, suggest appropriate values for each field.

Rules:
- Use the profile data to fill mapped fields
- For unmapped fields, make reasonable suggestions based on context
- Format dates, phone numbers, etc. appropriately for the field
- Return confidence scores (0.0-1.0) for each suggestion

Respond with JSON:
{
  "filled_fields": [
    {"field_name": "...", "suggested_value": "...", "confidence": 0.0-1.0}
  ]
}"""


class FormFiller:
    """Fills form fields using AI and user profile data."""

    async def fill_form(
        self,
        form_fields: list[dict[str, Any]],
        profile_data: dict[str, Any],
    ) -> list[dict[str, Any]]:
        """Fill form fields using profile data and AI suggestions."""
        # First, get field mappings
        mappings = await field_mapper.map_fields(form_fields)

        # Build context for AI
        profile_summary = "\n".join(
            f"- {k}: {v}" for k, v in profile_data.items() if v
        )
        fields_with_mappings = "\n".join(
            f"- {m.get('field_name', '')}: mapped_to={m.get('profile_field', 'none')}"
            for m in mappings
        )

        messages = [
            {"role": "system", "content": FORM_FILL_PROMPT},
            {
                "role": "user",
                "content": (
                    f"Profile data:\n{profile_summary}\n\n"
                    f"Form fields with mappings:\n{fields_with_mappings}"
                ),
            },
        ]

        result = await ai_provider.chat_completion_json(messages)
        return result.get("filled_fields", [])


form_filler = FormFiller()
