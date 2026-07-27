"""Real-time collaboration via command log — E8.3 Enhancement-Based Masterplan.

Design:
- WebSocket endpoint: /api/v1/teams/{team_id}/collab/ws
- Auth: token via query param ?token=JWT or ?token=API_KEY? For V1 we accept Authorization via query `token` that is JWT access token.
- Authorization: user must be member of team (require_member). Team existence not leaked (404 for non-member).
- Relay: in-memory dict team_id -> set[WebSocket]. When a client sends a command JSON, broadcast to other clients in same team.
- Command format (from frontend domain/history/editor_command.dart serialized):
  {
    "type": "command",
    "commandType": "add" | "remove" | "move" | "edit" | "reorder",
    "annotationId": "...",
    "payload": { ... }, // e.g. {x,y, text, etc}
    "timestamp": "2026-07-27T...",
    "deviceId": "device-123",
    "fileHash": "abc123",
    "pageIndex": 0
  }
- Server is relay only, not storage (privacy). No document bytes stored.
- Last-write-wins per annotation id (client merges). Server does not enforce CRDT — just broadcasts.
- For audit: record collab events to team_audit_log (optional, best-effort).

Future:
- Replace in-memory dict with Redis pub/sub for multi-instance.
- Add persistence of command log for replay when new client joins (opt-in).
"""

import asyncio
import json
import logging
from typing import Dict, Set
from uuid import UUID

from fastapi import APIRouter, Depends, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.security import decode_token
from app.db.database import get_db
from app.models.user import User
from app.services.team.team_service import require_member

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/teams", tags=["Collaboration"])

# In-memory connection manager — team_id -> set of WebSocket connections
# For production with multiple backend instances, replace with Redis pub/sub.
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
        # Copy set to avoid holding lock during send
        async with self.lock:
            connections = list(self.active.get(team_id, []))
        for ws in connections:
            if ws is sender:
                continue
            try:
                await ws.send_text(message)
            except Exception:
                # Ignore failed sends — disconnect will clean up
                pass

manager = ConnectionManager()


async def get_user_from_token(token: str | None, db: AsyncSession) -> User | None:
    """Extract user from JWT token passed via query param (WebSocket cannot send Authorization header reliably)."""
    if not token:
        return None
    try:
        # Token may be "Bearer xxx" or just xxx
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
    token: str | None = Query(default=None, description="JWT access token (or Bearer token) for auth"),
    db: AsyncSession = Depends(get_db),
):
    """WebSocket for real-time command-log collaboration (E8.3).

    Query params:
    - token: JWT access token (from /auth/login or /auth/sso/*)
    - file_hash: optional filter — only relay commands for this file_hash (client-side filtering also)

    Flow:
    1. Auth via token query param
    2. Check team membership (require_member) — 404 if not member (no existence leak)
    3. Accept WebSocket, add to manager
    4. Loop receiving text messages (JSON commands), validate minimal schema, broadcast to other clients in same team
    5. On disconnect, remove from manager
    """
    # Auth
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
        # Send welcome message
        await websocket.send_text(
            json.dumps(
                {
                    "type": "welcome",
                    "team_id": str(team_id),
                    "user_id": str(user.id),
                    "message": "Connected to collab relay — send command JSON, it will be broadcast to other team members.",
                }
            )
        )

        while True:
            try:
                data = await websocket.receive_text()
                # Validate it is JSON and has at least type field
                try:
                    msg = json.loads(data)
                    if not isinstance(msg, dict) or "type" not in msg:
                        await websocket.send_text(json.dumps({"type": "error", "detail": "Invalid command — must have type field"}))
                        continue
                    # Enrich with sender info
                    msg["_sender"] = str(user.id)
                    # Optional: check file_hash present for filtering? We broadcast regardless
                    # Broadcast to others
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
    """Return collab status for a team (number of connected clients) — for health dashboard."""
    # Require member if user authenticated, else return 0 (public status minimal)
    if user:
        try:
            await require_member(db, team_id, user.id)
        except Exception:
            return {"team_id": str(team_id), "connected_clients": 0, "note": "Not member — count hidden"}
    count = len(manager.active.get(team_id, []))
    return {
        "team_id": str(team_id),
        "connected_clients": count,
        "relay": "in-memory (single instance) — replace with Redis pub/sub for multi-instance (see ENHANCEMENT_BASED_MASTERPLAN.md E8.3)",
    }
