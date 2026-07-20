"""Authentication endpoints: register, login, token refresh, profile, password.

Tokens are JWTs minted by ``app.core.security``. Access tokens are short-lived
(``JWT_ACCESS_TOKEN_EXPIRE_MINUTES``); refresh tokens are long-lived
(``JWT_REFRESH_TOKEN_EXPIRE_DAYS``) and are rotated on every refresh.
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.core.config import settings
from app.core.exceptions import AuthenticationError, ValidationError
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
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


@router.post("/login", response_model=TokenResponse)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Authenticate with email + password and return a token pair."""
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()

    # Same generic error whether the email is unknown or the password is wrong,
    # so the endpoint does not leak which emails are registered.
    if user is None or not verify_password(request.password, user.hashed_password):
        raise AuthenticationError("Invalid email or password")
    if not user.is_active:
        raise AuthenticationError("User account is deactivated")

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

    user_id = payload.get("sub")
    if not user_id:
        raise AuthenticationError("Invalid token")

    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None or not user.is_active:
        raise AuthenticationError("User not found or deactivated")

    # Rotate: a new refresh token is issued alongside the new access token.
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
