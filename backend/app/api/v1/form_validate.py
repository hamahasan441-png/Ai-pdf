"""Form field value validation endpoint.

Validates values before placing them on a form — catches common errors like
invalid emails, wrong date formats, bad IBANs. Uses the FieldValidator service.
"""

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.ai.field_validator import field_validator

router = APIRouter(prefix="/forms", tags=["Forms"])


class FieldValidation(BaseModel):
    name: str
    value: str
    field_type: str  # email | phone | date | number | iban | zip | name | text


class ValidateRequest(BaseModel):
    fields: list[FieldValidation] = Field(..., max_length=100)


class FieldValidationResult(BaseModel):
    name: str
    valid: bool
    error: str = ""
    suggestion: str = ""


class ValidateResponse(BaseModel):
    results: list[FieldValidationResult]
    all_valid: bool


@router.post("/validate", response_model=ValidateResponse)
async def validate_form_fields(req: ValidateRequest):
    """Validate multiple form field values at once.

    Not metered (pure validation, no AI). Returns per-field results with
    error messages and suggestions for corrections.
    """
    results = []
    all_valid = True
    for f in req.fields:
        r = field_validator.validate(f.value, f.field_type)
        results.append(FieldValidationResult(
            name=f.name,
            valid=r.valid,
            error=r.error,
            suggestion=r.suggestion,
        ))
        if not r.valid:
            all_valid = False

    return ValidateResponse(results=results, all_valid=all_valid)
