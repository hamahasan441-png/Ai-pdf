"""Profile service with encryption for sensitive data."""

import json
import uuid
from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import decrypt_data, encrypt_data
from app.models.user import UserProfile
from app.schemas.profile import ProfileResponse, ProfileUpdateRequest


class ProfileService:
    """Manages user profiles with encrypted storage."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_profile(self, user_id: uuid.UUID) -> ProfileResponse:
        """Get decrypted user profile."""
        profile = await self._get_or_create_profile(user_id)
        return self._decrypt_profile(profile)

    async def update_profile(
        self, user_id: uuid.UUID, request: ProfileUpdateRequest
    ) -> ProfileResponse:
        """Update profile with encrypted values."""
        profile = await self._get_or_create_profile(user_id)

        # Encrypt and store each field
        field_mapping = {
            "first_name": "first_name_encrypted",
            "last_name": "last_name_encrypted",
            "phone": "phone_encrypted",
            "address": "address_encrypted",
            "city": "city_encrypted",
            "state": "state_encrypted",
            "zip_code": "zip_code_encrypted",
            "country": "country_encrypted",
            "date_of_birth": "date_of_birth_encrypted",
            "ssn": "ssn_encrypted",
        }

        update_data = request.model_dump(exclude_unset=True)

        for field_name, encrypted_col in field_mapping.items():
            if field_name in update_data and update_data[field_name] is not None:
                setattr(profile, encrypted_col, encrypt_data(update_data[field_name]))

        # Handle custom fields
        if "custom_fields" in update_data and update_data["custom_fields"]:
            profile.custom_fields_encrypted = encrypt_data(
                json.dumps(update_data["custom_fields"])
            )

        await self.db.flush()
        return self._decrypt_profile(profile)

    async def get_profile_data_for_filling(
        self, user_id: uuid.UUID
    ) -> dict[str, Optional[str]]:
        """Get decrypted profile data as dict for form filling."""
        profile = await self._get_or_create_profile(user_id)
        response = self._decrypt_profile(profile)
        return response.model_dump(exclude={"ssn_last_four"})

    async def _get_or_create_profile(self, user_id: uuid.UUID) -> UserProfile:
        """Get existing profile or create a new one."""
        result = await self.db.execute(
            select(UserProfile).where(UserProfile.user_id == user_id)
        )
        profile = result.scalar_one_or_none()

        if not profile:
            profile = UserProfile(user_id=user_id)
            self.db.add(profile)
            await self.db.flush()

        return profile

    def _decrypt_profile(self, profile: UserProfile) -> ProfileResponse:
        """Decrypt all profile fields into a response object."""

        def safe_decrypt(value: Optional[str]) -> Optional[str]:
            if value is None:
                return None
            try:
                return decrypt_data(value)
            except Exception:
                return None

        # Decrypt SSN and show only last 4
        ssn_full = safe_decrypt(profile.ssn_encrypted)
        ssn_last_four = ssn_full[-4:] if ssn_full and len(ssn_full) >= 4 else None

        # Decrypt custom fields
        custom_fields = None
        if profile.custom_fields_encrypted:
            try:
                decrypted = decrypt_data(profile.custom_fields_encrypted)
                custom_fields = json.loads(decrypted)
            except Exception:
                custom_fields = None

        return ProfileResponse(
            first_name=safe_decrypt(profile.first_name_encrypted),
            last_name=safe_decrypt(profile.last_name_encrypted),
            phone=safe_decrypt(profile.phone_encrypted),
            address=safe_decrypt(profile.address_encrypted),
            city=safe_decrypt(profile.city_encrypted),
            state=safe_decrypt(profile.state_encrypted),
            zip_code=safe_decrypt(profile.zip_code_encrypted),
            country=safe_decrypt(profile.country_encrypted),
            date_of_birth=safe_decrypt(profile.date_of_birth_encrypted),
            ssn_last_four=ssn_last_four,
            custom_fields=custom_fields,
        )
