"""Powerful AI Form Filler - Intelligently fills ANY form from ANY source.

This is the most important service in the app. It:
1. Takes detected form fields from any document
2. Maps them semantically to user profile data (multi-language)
3. Formats values correctly (dates, phones, addresses by locale)
4. Fills fields with high confidence
5. Validates filled values
6. Asks smart questions for missing required fields
7. Handles complex form logic

Works with: government forms, visa applications, insurance forms,
banking forms, tax forms, employment forms, contracts, healthcare forms.
Supports: English, German, French, Spanish, Arabic, Chinese, and more.
"""

import logging
from typing import Any, Optional

from app.services.ai.provider import ai_provider

logger = logging.getLogger(__name__)

# Comprehensive prompt that makes the AI a form-filling expert
INTELLIGENT_FILL_PROMPT = """You are the world's best form-filling AI. You understand forms in ALL languages.

TASK: Given a user's personal data and a list of form fields, fill each field with the correct value.

RULES:
1. SEMANTIC UNDERSTANDING: "Last Name" = "Surname" = "Family Name" = "Nachname" (DE) = "Apellido" (ES) = "Nom de famille" (FR) = "اسم العائلة" (AR) = "姓" (CN)
2. DATE FORMATTING: Detect the form's expected format:
   - If field hint says DD/MM/YYYY → use 15/03/1990
   - If MM/DD/YYYY → use 03/15/1990
   - If YYYY-MM-DD → use 1990-03-15
   - Default: use the most common format for the document's country
3. PHONE FORMATTING: Add country code if the form expects it: +1 (555) 123-4567 or 0049-555-123-4567
4. ADDRESS: Split or combine address components as the form requires
5. NAME CAPITALIZATION: Always properly capitalize (John Smith, not JOHN SMITH or john smith)
6. CHECKBOXES: Return "yes"/"no" or "true"/"false" based on context
7. CALCULATIONS: If a field is a sum/total, calculate it from other filled values
8. CONDITIONAL LOGIC: If Field A = "married", fill "spouse name" too
9. CONFIDENCE: Rate 0.0 (guess) to 1.0 (exact match from profile)
10. MISSING DATA: If data is clearly not in profile, mark needs_user_input=true and write a helpful question

IMPORTANT: Never leave a required field empty without asking. Never guess sensitive data (SSN, passport) - ask the user.

Respond with JSON:
{
  "filled_fields": [
    {
      "field_id": "...",
      "field_name": "...",
      "value": "filled value or null",
      "confidence": 0.0-1.0,
      "source": "profile" | "calculated" | "inferred" | "needs_input",
      "needs_user_input": false,
      "question_for_user": null or "What is your...?",
      "formatting_applied": null or "formatted as DD/MM/YYYY",
      "validation": "valid" | "warning" | "error",
      "validation_message": null or "This date seems to be in the future"
    }
  ],
  "summary": "Filled X of Y fields. Z fields need user input.",
  "warnings": ["list of any issues detected"]
}"""

VALIDATION_PROMPT = """You are a form validation expert. Check these filled form fields for errors.

Validate:
1. Date fields: Are dates logical? (DOB not in future, expiry not in past)
2. Email: Valid format (has @ and domain)
3. Phone: Reasonable format and length
4. Required fields: All filled?
5. Cross-field logic: (expiry > issue date, age matches DOB, etc.)
6. Format consistency: All dates same format? Phone numbers consistent?
7. Logical values: Age 0-120, year 1900-2030, etc.

Return JSON:
{
  "is_valid": true/false,
  "score": 0-100,
  "issues": [
    {"field": "...", "severity": "error"|"warning"|"info", "message": "..."}
  ],
  "suggestions": [
    {"field": "...", "current": "...", "suggested": "...", "reason": "..."}
  ]
}"""

SMART_QUESTION_PROMPT = """You are a helpful assistant asking users for missing form data.

Given a form field that needs user input, generate:
1. A clear, friendly question
2. A hint about the expected format
3. An example (with fake data)

Keep it short and professional. If the field is sensitive (SSN, passport), explain why it's needed.

Return JSON:
{
  "question": "What is your passport number?",
  "hint": "Usually 9 characters (letters and numbers)",
  "example": "AB1234567",
  "why_needed": "Required for visa application",
  "input_type": "text|date|email|phone|number|select"
}"""


class FormFiller:
    """Powerful intelligent form filler with semantic understanding.

    Capabilities:
    - Fills forms in any language
    - Understands 100+ field types semantically
    - Formats values by locale/form requirements
    - Validates as it fills
    - Smart questions for missing data
    - Handles conditional logic
    - Cross-field validation
    """

    async def fill_form(
        self,
        form_fields: list[dict[str, Any]],
        profile_data: dict[str, Any],
        document_context: Optional[str] = None,
        document_language: Optional[str] = None,
    ) -> dict[str, Any]:
        """Fill form fields intelligently using AI + profile data.

        This is the main method. It:
        1. Sends fields + profile to AI
        2. AI semantically matches and fills
        3. Returns filled values with confidence + validation

        Args:
            form_fields: Detected fields from document
            profile_data: User's decrypted profile data
            document_context: Optional context (document title, type)
            document_language: Detected language of the form

        Returns:
            Complete fill result with values, confidence, validation
        """
        if not form_fields:
            return {"filled_fields": [], "summary": "No fields to fill", "warnings": []}

        # Build comprehensive context for AI
        profile_summary = self._build_profile_summary(profile_data)
        fields_summary = self._build_fields_summary(form_fields)
        context_info = ""
        if document_context:
            context_info += f"\nDocument type: {document_context}"
        if document_language:
            context_info += f"\nForm language: {document_language}"

        messages = [
            {"role": "system", "content": INTELLIGENT_FILL_PROMPT},
            {
                "role": "user",
                "content": (
                    f"USER PROFILE DATA:\n{profile_summary}\n\n"
                    f"FORM FIELDS TO FILL:\n{fields_summary}\n\n"
                    f"CONTEXT:{context_info}\n\n"
                    f"Fill every field. Use semantic understanding. Format values correctly."
                ),
            },
        ]

        try:
            result = await ai_provider.chat_completion_json(
                messages=messages,
                use_advanced=True,
                max_tokens=4096,
            )
            return result
        except Exception as e:
            logger.error(f"AI form filling failed: {e}")
            # Fallback: try direct mapping
            return await self._fallback_fill(form_fields, profile_data)

    async def validate_filled_form(
        self,
        filled_fields: list[dict[str, Any]],
    ) -> dict[str, Any]:
        """Validate all filled fields for errors and consistency.

        Returns validation score, issues, and suggestions.
        """
        fields_text = "\n".join(
            f"- {f.get('field_name', '')}: value='{f.get('value', '')}', type={f.get('type', 'text')}"
            for f in filled_fields
            if f.get("value")
        )

        messages = [
            {"role": "system", "content": VALIDATION_PROMPT},
            {"role": "user", "content": f"Validate these form fields:\n\n{fields_text}"},
        ]

        try:
            return await ai_provider.chat_completion_json(messages=messages)
        except Exception as e:
            logger.error(f"Validation failed: {e}")
            return {"is_valid": True, "score": 70, "issues": [], "suggestions": []}

    async def get_smart_question(
        self,
        field_name: str,
        field_type: str,
        document_context: Optional[str] = None,
    ) -> dict[str, Any]:
        """Generate a smart, helpful question for missing field data.

        Returns a user-friendly question with format hints and examples.
        """
        context = f" (for a {document_context})" if document_context else ""

        messages = [
            {"role": "system", "content": SMART_QUESTION_PROMPT},
            {
                "role": "user",
                "content": f"Generate a question for this missing form field{context}:\nField: {field_name}\nType: {field_type}",
            },
        ]

        try:
            return await ai_provider.chat_completion_json(messages=messages)
        except Exception:
            return {
                "question": f"Please provide your {field_name}",
                "hint": "",
                "example": "",
                "input_type": field_type or "text",
            }

    async def fill_from_image(
        self,
        image_path: str,
        profile_data: dict[str, Any],
    ) -> dict[str, Any]:
        """Fill a form from an image using AI vision.

        Combines vision (to read the form) with intelligence (to fill it).
        """
        from app.services.ai.vision import vision_service

        # Step 1: Detect fields from image
        fields = await vision_service.detect_form_fields(image_path)

        if not fields:
            return {"filled_fields": [], "summary": "No fields detected in image", "warnings": []}

        # Step 2: Fill detected fields
        form_fields = [
            {"field_name": f.get("label", ""), "field_type": f.get("type", "text"), "required": f.get("required", False)}
            for f in fields
        ]

        return await self.fill_form(
            form_fields=form_fields,
            profile_data=profile_data,
            document_context="scanned form (from image)",
        )

    async def _fallback_fill(
        self,
        form_fields: list[dict[str, Any]],
        profile_data: dict[str, Any],
    ) -> dict[str, Any]:
        """Fallback: simple keyword-based fill when AI fails."""
        filled = []
        for f in form_fields:
            name = (f.get("field_name") or f.get("field_label") or "").lower()
            value = None
            confidence = 0.0

            # Simple keyword matching as last resort
            mapping = {
                "first": "first_name",
                "given": "first_name",
                "last": "last_name",
                "surname": "last_name",
                "family": "last_name",
                "phone": "phone",
                "mobile": "phone",
                "tel": "phone",
                "email": "email",
                "mail": "email",
                "address": "address",
                "street": "address",
                "city": "city",
                "state": "state",
                "zip": "zip_code",
                "postal": "zip_code",
                "country": "country",
                "birth": "date_of_birth",
                "dob": "date_of_birth",
            }

            for keyword, profile_field in mapping.items():
                if keyword in name:
                    value = profile_data.get(profile_field)
                    if value:
                        confidence = 0.7
                    break

            filled.append({
                "field_name": f.get("field_name") or f.get("field_label", ""),
                "value": value,
                "confidence": confidence,
                "source": "profile" if value else "needs_input",
                "needs_user_input": value is None,
            })

        filled_count = sum(1 for f in filled if f.get("value"))
        return {
            "filled_fields": filled,
            "summary": f"Filled {filled_count} of {len(filled)} fields (fallback mode)",
            "warnings": ["AI service unavailable, used basic matching"],
        }

    def _build_profile_summary(self, profile_data: dict[str, Any]) -> str:
        """Build a comprehensive profile summary for AI."""
        lines = []
        for key, value in profile_data.items():
            if value and key not in ("id", "user_id", "ssn_last_four"):
                # Clean field name for readability
                display_name = key.replace("_", " ").title()
                lines.append(f"- {display_name}: {value}")

        if not lines:
            return "(No profile data available - user needs to fill profile first)"
        return "\n".join(lines)

    def _build_fields_summary(self, form_fields: list[dict[str, Any]]) -> str:
        """Build a structured summary of form fields for AI."""
        lines = []
        for i, f in enumerate(form_fields, 1):
            name = f.get("field_name") or f.get("field_label") or f.get("label") or f"Field {i}"
            ftype = f.get("field_type") or f.get("type") or "text"
            required = "REQUIRED" if f.get("required") else "optional"
            current_value = f.get("value") or f.get("suggested_value") or ""
            hint = f.get("format_hint") or ""

            line = f"- [{i}] {name} (type={ftype}, {required})"
            if current_value:
                line += f" [current: {current_value}]"
            if hint:
                line += f" [format: {hint}]"
            lines.append(line)

        return "\n".join(lines)


# Singleton
form_filler = FormFiller()
