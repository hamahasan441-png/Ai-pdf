"""Profile request/response schemas."""

from typing import Optional

from pydantic import BaseModel


class ProfileUpdateRequest(BaseModel):
    """Update user profile fields."""

    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    zip_code: Optional[str] = None
    country: Optional[str] = None
    date_of_birth: Optional[str] = None
    ssn: Optional[str] = None
    custom_fields: Optional[dict] = None


class ProfileResponse(BaseModel):
    """User profile response (decrypted)."""

    first_name: Optional[str] = None
    last_name: Optional[str] = None
    phone: Optional[str] = None
    address: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    zip_code: Optional[str] = None
    country: Optional[str] = None
    date_of_birth: Optional[str] = None
    ssn_last_four: Optional[str] = None
    custom_fields: Optional[dict] = None

    class Config:
        from_attributes = True
