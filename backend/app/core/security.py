"""Security utilities: JWT token handling and data encryption."""

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import bcrypt
import jwt
from cryptography.fernet import Fernet

from app.core.config import settings

# bcrypt only ever uses the first 72 BYTES of a password. Newer bcrypt releases
# raise ValueError on longer input instead of silently truncating, so we
# truncate explicitly at the application layer for deterministic behavior.
# Using bcrypt directly (instead of passlib) avoids the passlib 1.7.4 + modern
# bcrypt incompatibility that raised "password cannot be longer than 72 bytes"
# during hashing. bcrypt hashes are the standard "$2b$" format, so any hashes
# previously created via passlib remain verifiable.
_BCRYPT_MAX_BYTES = 72


def _pw_bytes(password: str) -> bytes:
    return password.encode("utf-8")[:_BCRYPT_MAX_BYTES]


def hash_password(password: str) -> str:
    """Hash a plaintext password with bcrypt (72-byte safe)."""
    return bcrypt.hashpw(_pw_bytes(password), bcrypt.gensalt(rounds=12)).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a bcrypt hash."""
    try:
        return bcrypt.checkpw(_pw_bytes(plain_password), hashed_password.encode("utf-8"))
    except (ValueError, TypeError):
        # Malformed/empty stored hash → treat as a failed match, never crash.
        return False


def create_access_token(
    subject: str,
    extra_claims: Optional[dict[str, Any]] = None,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Create a JWT access token."""
    if expires_delta is None:
        expires_delta = timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)

    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "iat": now,
        "exp": now + expires_delta,
        "type": "access",
    }
    if extra_claims:
        payload.update(extra_claims)

    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(subject: str) -> str:
    """Create a JWT refresh token."""
    expires_delta = timedelta(days=settings.JWT_REFRESH_TOKEN_EXPIRE_DAYS)
    now = datetime.now(timezone.utc)
    payload = {
        "sub": subject,
        "iat": now,
        "exp": now + expires_delta,
        "type": "refresh",
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str) -> dict[str, Any]:
    """Decode and validate a JWT token."""
    return jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
    )


# Data encryption for sensitive profile fields
def get_fernet() -> Fernet:
    """Get a Fernet instance for symmetric encryption."""
    key = settings.ENCRYPTION_KEY.encode()
    # Pad or hash key to 32 bytes for Fernet (requires url-safe base64 encoded 32 bytes)
    import base64
    import hashlib

    hashed = hashlib.sha256(key).digest()
    fernet_key = base64.urlsafe_b64encode(hashed)
    return Fernet(fernet_key)


def encrypt_data(plaintext: str) -> str:
    """Encrypt sensitive data using Fernet symmetric encryption."""
    f = get_fernet()
    return f.encrypt(plaintext.encode()).decode()


def decrypt_data(ciphertext: str) -> str:
    """Decrypt data encrypted with encrypt_data."""
    f = get_fernet()
    return f.decrypt(ciphertext.encode()).decode()
