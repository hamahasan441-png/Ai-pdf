"""True redaction endpoint — E1.7 Enhancement-Based Masterplan (Phase 5).

Unlike whiteout (which covers content with a white box but leaves underlying text selectable),
true redaction REMOVES the underlying text/images via PyMuPDF redact annotations + apply.

Flow:
- POST /document-ai/redact (multipart): file + JSON areas + optional fill color
- Areas: list of {page: 0-based, x0,y0,x1,y1 normalized 0..1} — from editor_redaction_overlay.dart
- For each area: convert normalized to PDF rect (page.rect), add_redact_annot, set fill, apply_redactions()
- Returns redacted PDF bytes as application/pdf + audit log entry if team context provided

Security:
- Metered via tiered quota (same as other Document AI endpoints)
- Requires X-Entitlement-Token for Pro bypass
- Logs redaction to team audit if X-Team-Id header present and user is member

This is irreversible. An out-of-range page, an empty or non-finite
rectangle, a failed apply_redactions call, or a failed post-redaction check
rejects the whole request and returns no PDF. Coordinates are normalized
against the page as displayed (after /Rotate), the same space the editor uses.

The Flutter editor calls this endpoint only after the user agrees to upload the
file for that one redaction (see RedactionService.redactViaBackend). The
response carries X-Redaction-Verified only when every check in
secure_redact.verify_redaction passed.
"""

import io
import json
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from starlette.concurrency import run_in_threadpool
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.usage_limiter import UNLIMITED, check_and_increment_tiered, identity_for
from app.services.billing.quota_tiers import (
    get_quota,
    get_quota_with_team,
    parse_team_header,
    require_team_member,
)

from app.services.pdf.secure_redact import RedactionRejected, redact_pdf
from app.utils.filenames import safe_filename as _safe_filename

router = APIRouter(prefix="/document-ai", tags=["Document AI"])

# One request may not ask for more areas than this; each area is a separate
# PyMuPDF redaction and verification pass.
MAX_REDACT_AREAS = 500
_READ_CHUNK = 1024 * 1024


class RedactArea(BaseModel):
    page: int = Field(..., ge=0, description="0-based page index")
    x0: float = Field(..., ge=0, le=1, description="Normalized left")
    y0: float = Field(..., ge=0, le=1, description="Normalized top")
    x1: float = Field(..., ge=0, le=1, description="Normalized right")
    y1: float = Field(..., ge=0, le=1, description="Normalized bottom")
    fill: Optional[str] = Field("white", description="Fill color: white|black or hex #RRGGBB")


class RedactRequest(BaseModel):
    areas: List[RedactArea]


async def _meter(request: Request, user: Optional[User], db: AsyncSession) -> int:
    token = request.headers.get("X-Entitlement-Token")
    team_id_header = request.headers.get("X-Team-Id")
    tier = "free"
    limit = None
    source = "free"
    team_uuid = parse_team_header(team_id_header)
    if team_uuid:
        # 403 unless the caller is an authenticated member of the team.
        tier, limit, source = await get_quota_with_team(
            db, token, team_uuid, user_id=user.id if user else None
        )
    else:
        tier, limit = await get_quota(db, token)
        source = "entitlement" if token else "free"

    if limit is None:
        return UNLIMITED

    if source == "team" and team_uuid:
        identity = f"team:{team_uuid}"  # canonical form: one counter per team
    else:
        identity = identity_for(user, request)

    allowed, count = check_and_increment_tiered(identity, limit)
    if not allowed:
        detail = f"Team daily AI limit reached ({limit})." if source == "team" else "Daily AI limit reached. Upgrade to Pro."
        raise HTTPException(status_code=429, detail=detail)
    return max(0, limit - count)


@router.post("/redact")
async def redact_document(
    request: Request,
    file: UploadFile = File(..., description="PDF file to redact"),
    areas_json: str = Form(..., description="JSON array of RedactArea"),
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """True redaction — removes underlying content, not just whiteout cover (E1.7).

    Form fields:
    - file: PDF binary
    - areas_json: JSON string e.g. '[{"page":0,"x0":0.1,"y0":0.2,"x1":0.5,"y1":0.3,"fill":"white"}]'

    Returns: application/pdf redacted file.
    """
    if not settings.AI_API_KEY:
        # Allow redaction even without AI key? It's not AI, it's PDF operation — so don't require AI_API_KEY
        # But we still meter it as Document AI for quota consistency
        pass

    await _meter(request, user, db)

    # Parse areas. The error text never echoes the request back.
    try:
        areas_data = json.loads(areas_json)
    except ValueError:
        raise HTTPException(status_code=422, detail="Invalid areas_json: not JSON")
    if not isinstance(areas_data, list):
        raise HTTPException(status_code=422, detail="Invalid areas_json: expected a list")
    try:
        areas = [RedactArea(**a) for a in areas_data]
    except Exception:
        raise HTTPException(status_code=422, detail="Invalid areas_json: each area needs page, x0, y0, x1, y1 in 0..1")

    if not areas:
        raise HTTPException(status_code=422, detail="No redaction areas provided")
    if len(areas) > MAX_REDACT_AREAS:
        raise HTTPException(status_code=422, detail=f"At most {MAX_REDACT_AREAS} areas per request")

    # Read in chunks and stop at the limit instead of buffering any size.
    limit = settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024
    buffer = bytearray()
    try:
        while True:
            chunk = await file.read(_READ_CHUNK)
            if not chunk:
                break
            buffer.extend(chunk)
            if len(buffer) > limit:
                raise HTTPException(status_code=413, detail=f"File too large > {settings.MAX_UPLOAD_SIZE_MB}MB")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="Failed to read file")
    pdf_bytes = bytes(buffer)
    if not pdf_bytes:
        raise HTTPException(status_code=400, detail="Empty file")
    if b"%PDF-" not in pdf_bytes[:1024]:
        raise HTTPException(status_code=415, detail="The file is not a PDF")

    # Open with PyMuPDF, apply redactions, then reopen the output and verify
    # each region. Any failure rejects the whole request. The work is CPU
    # bound, so it runs off the event loop.
    try:
        report = await run_in_threadpool(
            redact_pdf,
            pdf_bytes,
            [
                {
                    "page": area.page,
                    "x0": area.x0,
                    "y0": area.y0,
                    "x1": area.x1,
                    "y1": area.y1,
                    "fill": area.fill,
                }
                for area in areas
            ],
        )
    except RedactionRejected as exc:
        raise HTTPException(status_code=exc.status, detail=str(exc)) from exc

    out_bytes = report.pdf

    team_uuid = parse_team_header(request.headers.get("X-Team-Id"))
    if team_uuid and user:
        # Membership is enforced before metering (_meter); re-check here so a
        # team audit entry is only ever written by a member of that team.
        await require_team_member(db, team_uuid, user.id)
        try:
            from app.services.team.team_service import record_audit

            await record_audit(
                db,
                team_id=team_uuid,
                actor_id=user.id,
                action="document.redact",
                target=_safe_filename(file.filename),
                detail=f"Redacted {len(areas)} areas",
            )
        except Exception:
            pass

    return StreamingResponse(
        io.BytesIO(out_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="redacted_{_safe_filename(file.filename)}"',
            "X-Redacted-Areas": str(report.regions),
            "X-Redaction-Verified": ",".join(report.checks),
            "X-Redaction-Objects-Removed": (
                f"annotations={report.annotations_removed};"
                f"links={report.links_removed};widgets={report.widgets_removed}"
            ),
            "X-Redaction-Hidden-Copies-Removed": ";".join(
                f"{k}={v}" for k, v in sorted(report.scrubbed.items())
            ),
            "X-Redaction-Occurrences-Elsewhere": str(report.occurrences_elsewhere),
        },
    )
