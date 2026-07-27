"""Authentication endpoints: register, login, token refresh, profile, password, 2FA.

Tokens are JWTs minted by ``app.core.security``. Access tokens are short-lived
(``JWT_ACCESS_TOKEN_EXPIRE_MINUTES``); refresh tokens are long-lived
(``JWT_REFRESH_TOKEN_EXPIRE_DAYS``) and are rotated on every refresh.

E5.2 — TOTP 2FA endpoints added: setup, verify/enable, disable, recovery.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.core.config import settings
from app.core.exceptions import AuthenticationError, ValidationError
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    decrypt_data,
    encrypt_data,
    hash_password,
    verify_password,
)
from app.db.database import get_db
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    PasswordChangeRequest,
    RefreshTokenRequest,
    RegisterRequest,
    TokenResponse,
    UserResponse,
)
from app.services.auth.totp import (
    generate_recovery_codes,
    generate_secret,
    get_otpauth_url,
    parse_recovery_codes,
    recovery_codes_hash_list,
    verify_totp,
)

router = APIRouter()


def _access_expiry_seconds() -> int:
    """Access-token lifetime in seconds (kept in sync with security.py)."""
    return settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60


def _issue_tokens(user: User) -> TokenResponse:
    """Mint a fresh access + refresh token pair for ``user``."""
    return TokenResponse(
        access_token=create_access_token(subject=str(user.id)),
        refresh_token=create_refresh_token(subject=str(user.id)),
        expires_in=_access_expiry_seconds(),
    )


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(
    request: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    """Register a new user account and return an initial token pair."""
    result = await db.execute(select(User).where(User.email == request.email))
    if result.scalar_one_or_none():
        raise ValidationError("Email already registered")

    user = User(
        email=request.email,
        hashed_password=hash_password(request.password),
        full_name=request.full_name,
    )
    db.add(user)
    await db.flush()

    return _issue_tokens(user)


# --- Login with optional 2FA --------------------------------------------

class _Login2FARequest(LoginRequest):
    totp_code: Optional[str] = None
    recovery_code: Optional[str] = None


@router.post("/login", response_model=TokenResponse)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Authenticate with email + password and return a token pair.

    E5.2 — If the user has TOTP enabled, the request must also include
    a valid totp_code or recovery_code (handled in the extended endpoint
    below via query, but we keep backward compatibility: if 2FA enabled and
    no code provided, raise 401 with detail \"2FA required\" so client can
    prompt.
    """
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()

    if user is None or not verify_password(request.password, user.hashed_password):
        raise AuthenticationError("Invalid email or password")
    if not user.is_active:
        raise AuthenticationError("User account is deactivated")

    # E5.2 — Check if 2FA enabled
    if user.totp_enabled:
        # The simple /login endpoint does not accept TOTP; client should use
        # /login/2fa. Raise specific error so client knows to prompt for second factor.
        raise AuthenticationError(
            "2FA required — provide totp_code or recovery_code via /auth/login/2fa"
        )

    return _issue_tokens(user)


class Login2FARequest(BaseModel):
    email: str
    password: str
    totp_code: Optional[str] = None
    recovery_code: Optional[str] = None


@router.post("/login/2fa", response_model=TokenResponse)
async def login_2fa(
    request: Login2FARequest,
    db: AsyncSession = Depends(get_db),
):
    """Authenticate with email+password + TOTP or recovery code (E5.2)."""
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()
    if user is None or not verify_password(request.password, user.hashed_password):
        raise AuthenticationError("Invalid email or password")
    if not user.is_active:
        raise AuthenticationError("User account is deactivated")

    if not user.totp_enabled:
        # No 2FA enabled — issue tokens directly
        return _issue_tokens(user)

    # 2FA enabled — need code
    if not request.totp_code and not request.recovery_code:
        raise AuthenticationError("2FA code required")

    if request.totp_code:
        if not user.totp_secret_encrypted:
            raise AuthenticationError("2FA not properly configured")
        try:
            secret = decrypt_data(user.totp_secret_encrypted)
        except Exception:
            raise AuthenticationError("2FA decryption failed")
        if not verify_totp(secret, request.totp_code):
            raise AuthenticationError("Invalid 2FA code")
    elif request.recovery_code:
        if not user.totp_recovery_codes_encrypted:
            raise AuthenticationError("No recovery codes configured")
        try:
            decrypted = decrypt_data(user.totp_recovery_codes_encrypted)
            codes = parse_recovery_codes(decrypted)
        except Exception:
            raise AuthenticationError("Recovery code decryption failed")
        # Normalize code (strip + uppercase)
        provided = request.recovery_code.strip().upper()
        if provided not in codes:
            raise AuthenticationError("Invalid recovery code")
        # Consume recovery code
        codes = [c for c in codes if c != provided]
        user.totp_recovery_codes_encrypted = encrypt_data(recovery_codes_hash_list(codes))
        # If no codes left, keep 2FA enabled but log warning (client should generate new)

    return _issue_tokens(user)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    request: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db),
):
    """Exchange a valid refresh token for a new (rotated) token pair."""
    try:
        payload = decode_token(request.refresh_token)
    except Exception:
        raise AuthenticationError("Invalid or expired refresh token")

    if payload.get("type") != "refresh":
        raise AuthenticationError("Invalid token type")

    subject = payload.get("sub")
    if not subject:
        raise AuthenticationError("Invalid token")
    try:
        user_uuid = uuid.UUID(str(subject))
    except (ValueError, TypeError):
        raise AuthenticationError("Invalid token subject")

    result = await db.execute(select(User).where(User.id == user_uuid))
    user = result.scalar_one_or_none()
    if user is None or not user.is_active:
        raise AuthenticationError("User not found or deactivated")

    return _issue_tokens(user)


@router.get("/me", response_model=UserResponse)
async def get_me(
    user: User = Depends(get_current_user),
):
    """Return the currently authenticated user's profile."""
    return UserResponse(
        id=str(user.id),
        email=user.email,
        full_name=user.full_name,
        is_active=user.is_active,
        is_verified=user.is_verified,
    )


@router.post("/change-password", status_code=status.HTTP_204_NO_CONTENT)
async def change_password(
    request: PasswordChangeRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Change the authenticated user's password after verifying the old one."""
    if not verify_password(request.current_password, user.hashed_password):
        raise AuthenticationError("Current password is incorrect")
    if request.new_password == request.current_password:
        raise ValidationError("New password must differ from the current password")

    user.hashed_password = hash_password(request.new_password)
    db.add(user)
    await db.flush()
    return None


# --- 2FA Endpoints E5.2 --------------------------------------------------


class Setup2FAResponse(BaseModel):
    secret: str
    otpauth_url: str
    qr_text: str  # same as otpauth_url for client QR generation


class Verify2FARequest(BaseModel):
    totp_code: str


class Verify2FAResponse(BaseModel):
    enabled: bool
    recovery_codes: list[str]


class Status2FAResponse(BaseModel):
    enabled: bool
    enabled_at: Optional[datetime] = None
    remaining_recovery_codes: int


@router.post("/2fa/setup", response_model=Setup2FAResponse)
async def setup_2fa(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Start 2FA setup — generate secret + otpauth URL (E5.2).

    The secret is stored encrypted but NOT marked enabled until verify.
    If a secret already exists and 2FA is already enabled, returns existing
    URL (does not rotate) unless forced.
    """
    if user.totp_enabled and user.totp_secret_encrypted:
        # Already enabled — return existing URL
        try:
            secret = decrypt_data(user.totp_secret_encrypted)
            url = get_otpauth_url(secret, user.email)
            return Setup2FAResponse(secret=secret, otpauth_url=url, qr_text=url)
        except Exception:
            pass  # fall through to regen

    secret = generate_secret()
    user.totp_secret_encrypted = encrypt_data(secret)
    # Do NOT enable yet
    user.totp_enabled = False
    db.add(user)
    await db.flush()

    url = get_otpauth_url(secret, user.email)
    return Setup2FAResponse(secret=secret, otpauth_url=url, qr_text=url)


@router.post("/2fa/verify", response_model=Verify2FAResponse)
async def verify_2fa(
    request: Verify2FARequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Verify TOTP code to enable 2FA — returns recovery codes (E5.2)."""
    if not user.totp_secret_encrypted:
        raise ValidationError("2FA not set up — call /auth/2fa/setup first")
    try:
        secret = decrypt_data(user.totp_secret_encrypted)
    except Exception:
        raise ValidationError("2FA secret decryption failed")

    if not verify_totp(secret, request.totp_code):
        raise AuthenticationError("Invalid TOTP code")

    # Generate recovery codes
    codes = generate_recovery_codes()
    user.totp_recovery_codes_encrypted = encrypt_data(recovery_codes_hash_list(codes))
    user.totp_enabled = True
    user.totp_enabled_at = datetime.now(timezone.utc)
    db.add(user)
    await db.flush()

    return Verify2FAResponse(enabled=True, recovery_codes=codes)


@router.get("/2fa/status", response_model=Status2FAResponse)
async def status_2fa(
    user: User = Depends(get_current_user),
):
    """Return 2FA status (E5.2)."""
    remaining = 0
    if user.totp_recovery_codes_encrypted:
        try:
            dec = decrypt_data(user.totp_recovery_codes_encrypted)
            remaining = len(parse_recovery_codes(dec))
        except Exception:
            remaining = 0

    return Status2FAResponse(
        enabled=user.totp_enabled,
        enabled_at=user.totp_enabled_at,
        remaining_recovery_codes=remaining,
    )


@router.post("/2fa/disable", status_code=status.HTTP_204_NO_CONTENT)
async def disable_2fa(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Disable 2FA (E5.2)."""
    user.totp_enabled = False
    user.totp_secret_encrypted = None
    user.totp_recovery_codes_encrypted = None
    user.totp_enabled_at = None
    db.add(user)
    await db.flush()
    return None


class Recovery2FAResponse(BaseModel):
    recovery_codes: list[str]


@router.post("/2fa/recovery-codes", response_model=Recovery2FAResponse)
async def regenerate_recovery_codes(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Regenerate recovery codes (must have 2FA enabled)."""
    if not user.totp_enabled:
        raise ValidationError("2FA not enabled")
    codes = generate_recovery_codes()
    user.totp_recovery_codes_encrypted = encrypt_data(recovery_codes_hash_list(codes))
    db.add(user)
    await db.flush()
    return Recovery2FAResponse(recovery_codes=codes)
