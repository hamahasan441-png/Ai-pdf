"""API key CRUD endpoints (Part 7.1 — Developer Platform).

Authenticated users can create, list, and revoke API keys. Keys are long-lived
bearer tokens for programmatic access (CI pipelines, webhook servers, partner
integrations). The full key is returned ONCE at creation and never stored in
cleartext on the server.
"""

import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.db.database import get_db
from app.models.api_key import ApiKey, generate_api_key
from app.models.user import User
from app.schemas.api_key import ApiKeyCreateRequest, ApiKeyCreateResponse, ApiKeyResponse

router = APIRouter(prefix="/api-keys", tags=["API Keys"])


@router.post("", response_model=ApiKeyCreateResponse, status_code=201)
async def create_api_key(
    request: ApiKeyCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new API key. The full key is returned ONLY in this response."""
    plaintext, key_hash = generate_api_key()

    team_id: Optional[uuid.UUID] = None
    if request.team_id:
        try:
            team_id = uuid.UUID(request.team_id)
        except ValueError as exc:
            raise HTTPException(status_code=422, detail="Invalid team_id") from exc

    api_key = ApiKey(
        owner_id=user.id,
        team_id=team_id,
        name=request.name,
        key_hash=key_hash,
        key_prefix=plaintext[:12],  # "aipdf_" + first 6 of the random part
    )
    db.add(api_key)
    await db.flush()

    return ApiKeyCreateResponse(
        id=str(api_key.id),
        name=api_key.name,
        key=plaintext,
        key_prefix=api_key.key_prefix,
        created_at=api_key.created_at,
    )


@router.get("", response_model=list[ApiKeyResponse])
async def list_api_keys(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all API keys for the authenticated user (active and revoked)."""
    keys = (
        await db.execute(
            select(ApiKey)
            .where(ApiKey.owner_id == user.id)
            .order_by(ApiKey.created_at.desc())
        )
    ).scalars().all()

    return [
        ApiKeyResponse(
            id=str(k.id),
            name=k.name,
            key_prefix=k.key_prefix,
            team_id=str(k.team_id) if k.team_id else None,
            created_at=k.created_at,
            last_used_at=k.last_used_at,
            revoked_at=k.revoked_at,
            is_active=k.is_active,
        )
        for k in keys
    ]


@router.delete("/{key_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_api_key(
    key_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Revoke an API key (soft-delete). It can no longer authenticate."""
    api_key = (
        await db.execute(
            select(ApiKey).where(ApiKey.id == key_id, ApiKey.owner_id == user.id)
        )
    ).scalar_one_or_none()

    if api_key is None:
        raise HTTPException(status_code=404, detail="API key not found")
    if api_key.revoked_at is not None:
        return None  # Already revoked — idempotent

    api_key.revoked_at = datetime.now(timezone.utc)
    await db.flush()
    return None
