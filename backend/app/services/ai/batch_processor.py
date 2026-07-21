"""Batch form processing — fill multiple forms with the same profile at once.

Power-user / enterprise feature: upload N forms, the system detects fields in
each, maps them to the user's profile, and returns N filled PDFs. Each form
gets the same processing as single-form AI Fill but in a batch.

### Architecture
- Input: list of (document_text, profile_data) pairs
- Processing: for each document, run field detection → profile matching → fill
- Output: list of filled field sets (the actual PDF filling uses /forms/acroform/fill)
- All on-device data; the server only sees the OCR'd text (not the PDF bytes)
"""

import logging
from dataclasses import dataclass

from app.services.ai.field_validator import field_validator

logger = logging.getLogger(__name__)


@dataclass
class BatchFormResult:
    """Result of processing one form in a batch."""
    doc_index: int
    doc_name: str
    fields_detected: int
    fields_filled: int
    fields_uncertain: int
    filled_values: dict  # {field_name: value}
    validation_errors: list  # [{field, error}]


class BatchProcessor:
    """Process multiple forms against a single profile."""

    def process_batch(
        self,
        documents: list[dict],
        profile: dict[str, str],
        field_mappings: dict[str, str] | None = None,
    ) -> list[BatchFormResult]:
        """Process a batch of documents.

        Args:
            documents: [{name, fields: [{label, type, ...}]}]
            profile: {profile_key: value} — the user's saved data
            field_mappings: optional {field_label: profile_key} overrides

        Returns:
            List of BatchFormResult for each document.
        """
        results = []
        for i, doc in enumerate(documents):
            result = self._process_single(i, doc, profile, field_mappings or {})
            results.append(result)
        return results

    def _process_single(
        self,
        index: int,
        doc: dict,
        profile: dict[str, str],
        mappings: dict[str, str],
    ) -> BatchFormResult:
        """Process a single form document."""
        doc_name = doc.get("name", f"document_{index}")
        fields = doc.get("fields", [])
        filled = {}
        uncertain = 0
        errors = []

        for field in fields:
            label = field.get("label", "")
            field_type = field.get("type", "text")
            profile_key = mappings.get(label, self._auto_map(label, profile))

            if profile_key and profile_key in profile:
                value = profile[profile_key]
                # Validate before placing.
                validation = field_validator.validate(value, field_type)
                if validation.valid:
                    filled[label] = value
                else:
                    errors.append({"field": label, "error": validation.error})
                    if validation.suggestion:
                        filled[label] = validation.suggestion
                    else:
                        uncertain += 1
            else:
                uncertain += 1

        return BatchFormResult(
            doc_index=index,
            doc_name=doc_name,
            fields_detected=len(fields),
            fields_filled=len(filled),
            fields_uncertain=uncertain,
            filled_values=filled,
            validation_errors=errors,
        )

    def _auto_map(self, label: str, profile: dict[str, str]) -> str | None:
        """Simple label → profile key matching (fuzzy)."""
        lower = label.lower().strip()
        # Direct match
        if lower in profile:
            return lower
        # Common mappings
        mappings = {
            "name": "full_name",
            "vorname": "first_name",
            "nachname": "last_name",
            "email": "email",
            "e-mail": "email",
            "telefon": "phone",
            "phone": "phone",
            "adresse": "address",
            "address": "address",
            "stadt": "city",
            "city": "city",
            "plz": "zip_code",
            "zip": "zip_code",
            "land": "country",
            "country": "country",
            "geburtsdatum": "date_of_birth",
            "date of birth": "date_of_birth",
        }
        mapped = mappings.get(lower)
        if mapped and mapped in profile:
            return mapped
        # Substring match
        for key in profile:
            if key in lower or lower in key:
                return key
        return None


# Singleton
batch_processor = BatchProcessor()
