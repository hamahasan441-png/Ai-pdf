"""Form field value validation service.

Validates user-entered or AI-suggested field values BEFORE placing them on the
form. Catches common errors (invalid email, wrong date format, bad IBAN) and
provides helpful error messages. Used by both the on-device auto-fill flow and
the backend understand-form endpoint.
"""

import re
from dataclasses import dataclass


@dataclass
class ValidationResult:
    valid: bool
    error: str = ""
    suggestion: str = ""  # corrected value if applicable


class FieldValidator:
    """Validate form field values by type."""

    def validate(self, value: str, field_type: str) -> ValidationResult:
        """Validate a value against its expected field type.

        Args:
            value: The value to validate.
            field_type: One of: email, phone, date, number, iban, zip, name, text.

        Returns:
            ValidationResult with valid=True if OK, else error message + suggestion.
        """
        if not value or not value.strip():
            return ValidationResult(valid=True)  # empty is OK (not required check)

        value = value.strip()
        validators = {
            "email": self._validate_email,
            "phone": self._validate_phone,
            "date": self._validate_date,
            "number": self._validate_number,
            "iban": self._validate_iban,
            "zip": self._validate_zip,
            "name": self._validate_name,
        }
        validator = validators.get(field_type)
        if validator is None:
            return ValidationResult(valid=True)  # text type: always valid
        return validator(value)

    def _validate_email(self, value: str) -> ValidationResult:
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        if re.match(pattern, value):
            return ValidationResult(valid=True)
        # Common fix: missing @
        if '@' not in value and '.' in value:
            return ValidationResult(valid=False, error="Missing @ symbol",
                                    suggestion=value.replace(' at ', '@'))
        return ValidationResult(valid=False, error="Invalid email format")

    def _validate_phone(self, value: str) -> ValidationResult:
        digits = re.sub(r'[^\d+]', '', value)
        if len(digits) >= 7 and len(digits) <= 16:
            return ValidationResult(valid=True)
        if len(digits) < 7:
            return ValidationResult(valid=False, error="Phone number too short")
        return ValidationResult(valid=False, error="Phone number too long")

    def _validate_date(self, value: str) -> ValidationResult:
        # Accept: DD.MM.YYYY, DD/MM/YYYY, YYYY-MM-DD, DD-MM-YYYY
        patterns = [
            (r'^\d{2}\.\d{2}\.\d{4}$', None),       # DD.MM.YYYY (German)
            (r'^\d{2}/\d{2}/\d{4}$', None),          # DD/MM/YYYY
            (r'^\d{4}-\d{2}-\d{2}$', None),          # YYYY-MM-DD (ISO)
            (r'^\d{2}-\d{2}-\d{4}$', None),          # DD-MM-YYYY
            (r'^\d{1,2}\.\d{1,2}\.\d{2,4}$', None),  # D.M.YY or DD.MM.YY
        ]
        for pattern, _ in patterns:
            if re.match(pattern, value):
                return ValidationResult(valid=True)
        return ValidationResult(valid=False, error="Unrecognized date format",
                                suggestion="Use DD.MM.YYYY")

    def _validate_number(self, value: str) -> ValidationResult:
        # Allow comma/dot as decimal separator, spaces as thousands separator
        cleaned = value.replace(' ', '').replace('.', '').replace(',', '.')
        try:
            float(cleaned)
            return ValidationResult(valid=True)
        except ValueError:
            return ValidationResult(valid=False, error="Not a valid number")

    def _validate_iban(self, value: str) -> ValidationResult:
        iban = value.replace(' ', '').upper()
        if len(iban) < 15 or len(iban) > 34:
            return ValidationResult(valid=False, error="IBAN length invalid")
        if not re.match(r'^[A-Z]{2}\d{2}[A-Z0-9]+$', iban):
            return ValidationResult(valid=False, error="IBAN format invalid")
        # Basic modulo-97 check
        rearranged = iban[4:] + iban[:4]
        numeric = ''.join(str(ord(c) - 55) if c.isalpha() else c for c in rearranged)
        if int(numeric) % 97 != 1:
            return ValidationResult(valid=False, error="IBAN checksum invalid")
        return ValidationResult(valid=True)

    def _validate_zip(self, value: str) -> ValidationResult:
        # German PLZ: exactly 5 digits; generic: 3-10 alphanumeric
        if re.match(r'^\d{5}$', value):
            return ValidationResult(valid=True)  # German
        if re.match(r'^[A-Z0-9]{3,10}$', value.upper().replace(' ', '')):
            return ValidationResult(valid=True)  # Generic
        return ValidationResult(valid=False, error="Invalid postal code format")

    def _validate_name(self, value: str) -> ValidationResult:
        if len(value) < 2:
            return ValidationResult(valid=False, error="Name too short")
        if any(c.isdigit() for c in value):
            return ValidationResult(valid=False, error="Name should not contain digits")
        return ValidationResult(valid=True)


# Singleton
field_validator = FieldValidator()
