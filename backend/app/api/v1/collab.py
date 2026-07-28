"""Real-time collaboration via command log — E8.3 Enhancement-Based Masterplan (Phase 5 full).

Design:
- WebSocket endpoint: /api/v1/teams/{team_id}/collab/ws
- Auth: token via query param ?token=JWT (Bearer supported)
- Authorization: user must be member of team (require_member). Team existence not leaked.
- Relay: in-memory dict team_id -> set[WebSocket]. When client sends command JSON, broadcast to other clients in same team.
- Persistence: commands are also stored in CollabCommandLog for replay when new client joins (opt-in, limited 1000 per file_hash)
- Command format (from frontend domain/history/editor_command.dart serialized):
  {
    "type": "command",
    "commandType": "add" | "remove" | "move" | "edit" | "reorder",
    "annotationId": "...",
    "payload": { ... },
    "timestamp": "2026-07-27T...",
    "deviceId": "device-123",
    "fileHash": "abc123",
    "pageIndex": 0
  }
- Server is relay + optional log for replay, not document storage (privacy). No document bytes stored.
- Last-write-wins per annotation id (client merges).
- Future: Redis pub/sub for multi-instance + encryption of payload if needed.
"""

import asyncio
import json
import logging
from typing import Dict, Set
from uuid import UUID

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_current_user, get_optional_user
from app.core.security import decode_token
from app.db.database import get_db
from app.models.collab import CollabCommandLog
from app.models.user import User
from app.services.team.team_service import require_member

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/teams", tags=["Collaboration"])


class ConnectionManager:
    def __init__(self):
        self.active: Dict[UUID, Set[WebSocket]] = {}
        self.lock = asyncio.Lock()

    async def connect(self, team_id: UUID, websocket: WebSocket):
        await websocket.accept()
        async with self.lock:
            if team_id not in self.active:
                self.active[team_id] = set()
            self.active[team_id].add(websocket)
        logger.info("Collab connect team=%s total=%s", team_id, len(self.active.get(team_id, [])))

    async def disconnect(self, team_id: UUID, websocket: WebSocket):
        async with self.lock:
            if team_id in self.active and websocket in self.active[team_id]:
                self.active[team_id].remove(websocket)
                if not self.active[team_id]:
                    del self.active[team_id]
        logger.info("Collab disconnect team=%s remaining=%s", team_id, len(self.active.get(team_id, [])))

    async def broadcast(self, team_id: UUID, message: str, sender: WebSocket):
        async with self.lock:
            connections = list(self.active.get(team_id, []))
        for ws in connections:
            if ws is sender:
                continue
            try:
                await ws.send_text(message)
            except Exception:
                pass


manager = ConnectionManager()


async def get_user_from_token(token: str | None, db: AsyncSession) -> User | None:
    if not token:
        return None
    try:
        if token.startswith("Bearer "):
            token = token[7:]
        payload = decode_token(token)
        if payload.get("type") != "access":
            return None
        sub = payload.get("sub")
        if not sub:
            return None
        from app.models.user import User as UserModel
        from sqlalchemy import select
        import uuid

        user_uuid = uuid.UUID(str(sub))
        result = await db.execute(select(UserModel).where(UserModel.id == user_uuid))
        user = result.scalar_one_or_none()
        if user and user.is_active:
            return user
    except Exception:
        return None
    return None


@router.websocket("/{team_id}/collab/ws")
async def collab_websocket(
    websocket: WebSocket,
    team_id: UUID,
    token: str | None = Query(default=None, description="JWT access token for auth"),
    file_hash: str | None = Query(default=None, description="Optional file_hash to filter and replay log"),
    db: AsyncSession = Depends(get_db),
):
    """WebSocket for real-time command-log collaboration (E8.3 full Phase 5).

    - Auth via ?token=JWT
    - On connect: if file_hash provided, sends recent command log for that file (replay) before welcome
    - Then loops receiving commands, validates type field, persists to CollabCommandLog (best-effort), broadcasts
    """
    user = await get_user_from_token(token, db)
    if not user:
        await websocket.close(code=4401, reason="Unauthorized — provide ?token=JWT")
        return

    try:
        await require_member(db, team_id, user.id)
    except Exception:
        await websocket.close(code=4404, reason="Team not found or not member")
        return

    await manager.connect(team_id, websocket)

    try:
        # Replay recent log if file_hash provided
        if file_hash:
            try:
                logs = (
                    await db.execute(
                        select(CollabCommandLog)
                        .where(CollabCommandLog.team_id == team_id, CollabCommandLog.file_hash == file_hash)
                        .order_by(CollabCommandLog.created_at.asc())
                        .limit(100)
                    )
                ).scalars().all()
                for log in logs:
                    try:
                        await websocket.send_text(log.command_json)
                    except Exception:
                        break
            except Exception as e:
                logger.warning("Collab replay failed: %s", e)

        await websocket.send_text(
            json.dumps(
                {
                    "type": "welcome",
                    "team_id": str(team_id),
                    "user_id": str(user.id),
                    "file_hash": file_hash,
                    "message": "Connected to collab relay — send command JSON, broadcast to team. Replay sent if file_hash provided.",
                }
            )
        )

        while True:
            try:
                data = await websocket.receive_text()
                try:
                    msg = json.loads(data)
                    if not isinstance(msg, dict) or "type" not in msg:
                        await websocket.send_text(json.dumps({"type": "error", "detail": "Invalid command — must have type"}))
                        continue
                    msg["_sender"] = str(user.id)

                    # Persist to log (best-effort) if file_hash present
                    try:
                        fh = msg.get("fileHash") or file_hash or "unknown"
                        ct = msg.get("commandType") or msg.get("type") or "unknown"
                        dev = msg.get("deviceId") or msg.get("device_id")

                        # Evict old if >1000 per file_hash
                        count = (
                            await db.execute(
                                select(func.count())
                                .select_from(CollabCommandLog)
                                .where(CollabCommandLog.team_id == team_id, CollabCommandLog.file_hash == fh)
                            )
                        ).scalar_one()
                        if count >= 1000:
                            # Delete oldest
                            oldest = (
                                await db.execute(
                                    select(CollabCommandLog)
                                    .where(CollabCommandLog.team_id == team_id, CollabCommandLog.file_hash == fh)
                                    .order_by(CollabCommandLog.created_at.asc())
                                    .limit(1)
                                )
                            ).scalar_one_or_none()
                            if oldest:
                                await db.delete(oldest)

                        log_entry = CollabCommandLog(
                            team_id=team_id,
                            file_hash=fh,
                            user_id=user.id,
                            device_id=dev,
                            command_type=ct,
                            command_json=data,
                        )
                        db.add(log_entry)
                        await db.flush()
                    except Exception as e:
                        logger.warning("Collab log persist failed: %s", e)

                    await manager.broadcast(team_id, json.dumps(msg), sender=websocket)
                except json.JSONDecodeError:
                    await websocket.send_text(json.dumps({"type": "error", "detail": "Invalid JSON"}))
            except WebSocketDisconnect:
                break
            except Exception as e:
                logger.warning("Collab ws error team=%s user=%s: %s", team_id, user.id, e)
                break
    finally:
        await manager.disconnect(team_id, websocket)


@router.get("/{team_id}/collab/status")
async def collab_status(
    team_id: UUID,
    user: User = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    if user:
        try:
            await require_member(db, team_id, user.id)
        except Exception:
            return {"team_id": str(team_id), "connected_clients": 0, "note": "Not member — count hidden"}
    count = len(manager.active.get(team_id, []))
    return {
        "team_id": str(team_id),
        "connected_clients": count,
        "relay": "in-memory + DB log replay (1000 per file_hash) — replace with Redis pub/sub for multi-instance (Phase 5 full)",
    }


@router.get("/{team_id}/collab/log")
async def collab_log(
    team_id: UUID,
    file_hash: str | None = Query(default=None),
    limit: int = Query(default=100, le=1000),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get collab command log for replay (E8.3 Phase 5) — owner/admin only? For V1 any member."""
    await require_member(db, team_id, user.id)

    q = select(CollabCommandLog).where(CollabCommandLog.team_id == team_id).order_by(CollabCommandLog.created_at.desc()).limit(limit)
    if file_hash:
        q = q.where(CollabCommandLog.file_hash == file_hash)

    logs = (await db.execute(q)).scalars().all()
    return {
        "team_id": str(team_id),
        "file_hash": file_hash,
        "count": len(logs),
        "commands": [
            {
                "id": str(log.id),
                "file_hash": log.file_hash,
                "user_id": str(log.user_id) if log.user_id else None,
                "device_id": log.device_id,
                "command_type": log.command_type,
                "command_json": log.command_json,
                "created_at": log.created_at.isoformat(),
            }
            for log in reversed(logs)  # ascending for replay
        ],
    }


@router.delete("/{team_id}/collab/log")
async def clear_collab_log(
    team_id: UUID,
    file_hash: str | None = Query(default=None),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Clear collab log for a file_hash or whole team (owner/admin only)."""
    from app.services.team.team_service import require_manager

    await require_manager(db, team_id, user.id)

    q = select(CollabCommandLog).where(CollabCommandLog.team_id == team_id)
    if file_hash:
        q = q.where(CollabCommandLog.file_hash == file_hash)

    logs = (await db.execute(q)).scalars().all()
    for log in logs:
        await db.delete(log)
    await db.flush()
    return {"deleted": len(logs), "team_id": str(team_id), "file_hash": file_hash}

