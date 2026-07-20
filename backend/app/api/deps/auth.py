"""Authentication dependencies for FastAPI routes."""

import uuid
from typing import Optional

from fastapi import Depends, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import AuthenticationError
from app.core.security import decode_token
from app.db.database import get_db
from app.models.user import User


def _parse_subject(user_id: object) -> Optional[uuid.UUID]:
    """Convert a JWT ``sub`` (stored as a string) into a UUID.

    Tokens carry the user id as a string; the ``Uuid`` column type expects a
    real ``uuid.UUID`` on every dialect (Postgres native + SQLite char), so we
    coerce here. Returns None when the value is missing or malformed.
    """
    if not user_id:
        return None
    try:
        return uuid.UUID(str(user_id))
    except (ValueError, TypeError, AttributeError):
        return None


async def get_current_user(
    authorization: str = Header(..., alias="Authorization"),
    db: AsyncSession = Depends(get_db),
) -> User:
    """Extract and validate user from JWT bearer token."""
    if not authorization.startswith("Bearer "):
        raise AuthenticationError("Invalid authorization header")

    token = authorization[7:]  # Remove "Bearer " prefix

    try:
        payload = decode_token(token)
    except Exception:
        raise AuthenticationError("Token expired or invalid")

    if payload.get("type") != "access":
        raise AuthenticationError("Invalid token")

    user_uuid = _parse_subject(payload.get("sub"))
    if user_uuid is None:
        raise AuthenticationError("Invalid token")

    # Fetch user from database
    result = await db.execute(select(User).where(User.id == user_uuid))
    user = result.scalar_one_or_none()

    if not user:
        raise AuthenticationError("User not found")

    if not user.is_active:
        raise AuthenticationError("User account is deactivated")

    return user


async def get_optional_user(
    authorization: Optional[str] = Header(None, alias="Authorization"),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    """Get user if authenticated, None if guest.

    This allows endpoints to work for both authenticated users
    and anonymous guests. Guest users get limited features.
    """
    if not authorization or not authorization.startswith("Bearer "):
        return None

    token = authorization[7:]
    try:
        payload = decode_token(token)
        if payload.get("type") != "access":
            return None
        user_uuid = _parse_subject(payload.get("sub"))
        if user_uuid is None:
            return None
        result = await db.execute(select(User).where(User.id == user_uuid))
        user = result.scalar_one_or_none()
        return user if user and user.is_active else None
    except Exception:
        return None
