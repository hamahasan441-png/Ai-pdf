"""Cloud Sync Opt-In endpoints — E8.2 Enhancement-Based Masterplan.

Opt-in encrypted sync for annotation persistence. The client encrypts locally
(Fernet) and uploads only ciphertext. Server never sees plaintext.

Endpoints:
- POST /sync/push — upload encrypted blob (file_hash + encrypted_blob + optional file_name, device_id)
- GET /sync/pull/{file_hash} — download latest blob for file_hash
- GET /sync/list — list all sync records for user (file_hash, file_name, version, updated_at, deleted)
- DELETE /sync/{file_hash} — soft-delete (marks deleted=True)

Security:
- All endpoints require authentication (get_current_user)
- Scoped to owner_id
- No document bytes synced unless user opts "sync documents" — here we only sync annotations (small JSON)

Conflict resolution: last-write-wins (updated_at), version increments. Client keeps revision history
locally via revision_history_service.dart, so both versions preserved even if last-write-wins.
"""

from datetime import datetime, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user
from app.db.database import get_db
from app.models.sync import DocumentSync
from app.models.user import User

router = APIRouter(prefix="/sync", tags=["Sync"])


class SyncPushRequest(BaseModel):
    file_hash: str = Field(..., min_length=8, max_length=128, description="SHA256 hash of file path/content")
    file_name: Optional[str] = Field(None, max_length=512)
    encrypted_blob: str = Field(..., min_length=10, description="Client-side Fernet ciphertext of annotation JSON")
    device_id: Optional[str] = Field(None, max_length=128)


class SyncPushResponse(BaseModel):
    file_hash: str
    version: int
    updated_at: datetime


class SyncPullResponse(BaseModel):
    file_hash: str
    file_name: Optional[str]
    encrypted_blob: str
    version: int
    updated_at: datetime
    device_id: Optional[str]
    deleted: bool


class SyncListItem(BaseModel):
    file_hash: str
    file_name: Optional[str]
    version: int
    updated_at: datetime
    device_id: Optional[str]
    deleted: bool


@router.post("/push", response_model=SyncPushResponse)
async def push_sync(
    request: SyncPushRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Push encrypted annotation blob for file_hash (create or update)."""
    # Find existing
    existing = (
        await db.execute(
            select(DocumentSync).where(
                DocumentSync.owner_id == user.id, DocumentSync.file_hash == request.file_hash
            )
        )
    ).scalar_one_or_none()

    now = datetime.now(timezone.utc)
    if existing:
        existing.encrypted_blob = request.encrypted_blob
        existing.file_name = request.file_name or existing.file_name
        existing.device_id = request.device_id or existing.device_id
        existing.version += 1
        existing.deleted = False
        existing.updated_at = now
        await db.flush()
        return SyncPushResponse(
            file_hash=existing.file_hash, version=existing.version, updated_at=existing.updated_at
        )
    else:
        record = DocumentSync(
            owner_id=user.id,
            file_hash=request.file_hash,
            file_name=request.file_name,
            encrypted_blob=request.encrypted_blob,
            device_id=request.device_id,
            version=1,
            deleted=False,
        )
        db.add(record)
        await db.flush()
        return SyncPushResponse(
            file_hash=record.file_hash, version=record.version, updated_at=record.updated_at
        )


@router.get("/pull/{file_hash}", response_model=SyncPullResponse)
async def pull_sync(
    file_hash: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Pull latest encrypted blob for file_hash."""
    record = (
        await db.execute(
            select(DocumentSync).where(
                DocumentSync.owner_id == user.id, DocumentSync.file_hash == file_hash
            )
        )
    ).scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="No sync record for this file_hash")
    if record.deleted:
        raise HTTPException(status_code=410, detail="Sync record deleted")

    return SyncPullResponse(
        file_hash=record.file_hash,
        file_name=record.file_name,
        encrypted_blob=record.encrypted_blob,
        version=record.version,
        updated_at=record.updated_at,
        device_id=record.device_id,
        deleted=record.deleted,
    )


@router.get("/list", response_model=List[SyncListItem])
async def list_sync(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all sync records for user (excluding deleted by default, include via ?include_deleted=true)."""
    records = (
        await db.execute(
            select(DocumentSync)
            .where(DocumentSync.owner_id == user.id)
            .order_by(DocumentSync.updated_at.desc())
        )
    ).scalars().all()

    return [
        SyncListItem(
            file_hash=r.file_hash,
            file_name=r.file_name,
            version=r.version,
            updated_at=r.updated_at,
            device_id=r.device_id,
            deleted=r.deleted,
        )
        for r in records
        if not r.deleted
    ]


@router.delete("/{file_hash}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sync(
    file_hash: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Soft-delete sync record (marks deleted=True, keeps row for audit)."""
    record = (
        await db.execute(
            select(DocumentSync).where(
                DocumentSync.owner_id == user.id, DocumentSync.file_hash == file_hash
            )
        )
    ).scalar_one_or_none()
    if not record:
        raise HTTPException(status_code=404, detail="No sync record")
    record.deleted = True
    record.updated_at = datetime.now(timezone.utc)
    await db.flush()
    return None


@router.get("/status")
async def sync_status(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Sync status for health dashboard (count, total size)."""
    records = (
        await db.execute(
            select(DocumentSync).where(DocumentSync.owner_id == user.id, DocumentSync.deleted.is_(False))
        )
    ).scalars().all()
    total_size = sum(len(r.encrypted_blob) for r in records)
    return {
        "enabled": True,
        "total_files": len(records),
        "total_encrypted_bytes": total_size,
        "note": "Client-side encrypted annotation sync — server never sees plaintext (E8.2). Opt-in only.",
    }
