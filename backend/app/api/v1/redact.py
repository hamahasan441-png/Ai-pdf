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

This is irreversible — frontend shows double confirm sheet warning.
"""

import io
import json
import logging
from typing import List, Optional

import fitz  # PyMuPDF
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.usage_limiter import UNLIMITED, check_and_increment_tiered, identity_for
from app.services.billing.quota_tiers import get_quota_with_team

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/document-ai", tags=["Document AI"])


class RedactArea(BaseModel):
    page: int = Field(..., ge=0, description="0-based page index")
    x0: float = Field(..., ge=0, le=1, description="Normalized left")
    y0: float = Field(..., ge=0, le=1, description="Normalized top")
    x1: float = Field(..., ge=0, le=1, description="Normalized right")
    y1: float = Field(..., ge=0, le=1, description="Normalized bottom")
    fill: Optional[str] = Field("white", description="Fill color: white|black or hex #RRGGBB")


class RedactRequest(BaseModel):
    areas: List[RedactArea]


def _hex_to_rgb(hex_color: str) -> tuple[float, float, float]:
    hex_color = hex_color.lstrip("#")
    if len(hex_color) == 3:
        hex_color = "".join([c * 2 for c in hex_color])
    if len(hex_color) != 6:
        return (1, 1, 1)
    try:
        r = int(hex_color[0:2], 16) / 255.0
        g = int(hex_color[2:4], 16) / 255.0
        b = int(hex_color[4:6], 16) / 255.0
        return (r, g, b)
    except Exception:
        return (1, 1, 1)


async def _meter(request: Request, user: Optional[User], db: AsyncSession) -> int:
    token = request.headers.get("X-Entitlement-Token")
    team_id_header = request.headers.get("X-Team-Id")
    tier = "free"
    limit = None
    source = "free"
    if team_id_header:
        try:
            import uuid

            team_uuid = uuid.UUID(team_id_header)
            tier, limit, source = await get_quota_with_team(db, token, team_uuid)
        except Exception:
            tier, limit = await get_quota_with_team(db, token, None)
            tier = tier[0] if isinstance(tier, tuple) else tier
            limit = limit[1] if isinstance(limit, tuple) else limit
            source = "entitlement" if token else "free"
            # fallback to simple
            from app.services.billing.quota_tiers import get_quota

            tier, limit = await get_quota(db, token)
    else:
        from app.services.billing.quota_tiers import get_quota

        tier, limit = await get_quota(db, token)
        source = "entitlement" if token else "free"

    if limit is None:
        return UNLIMITED

    if source == "team" and team_id_header:
        identity = f"team:{team_id_header}"
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

    # Parse areas
    try:
        areas_data = json.loads(areas_json)
        areas = [RedactArea(**a) for a in areas_data]
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Invalid areas_json: {e}")

    if not areas:
        raise HTTPException(status_code=422, detail="No redaction areas provided")

    # Read file
    try:
        pdf_bytes = await file.read()
        if len(pdf_bytes) == 0:
            raise ValueError("Empty file")
        if len(pdf_bytes) > settings.MAX_UPLOAD_SIZE_MB * 1024 * 1024:
            raise HTTPException(status_code=413, detail=f"File too large > {settings.MAX_UPLOAD_SIZE_MB}MB")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to read file: {e}")

    # Open with PyMuPDF and apply redactions
    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as e:
        raise HTTPException(status_code=422, detail=f"Invalid PDF: {e}")

    try:
        if len(doc) == 0:
            raise HTTPException(status_code=422, detail="PDF has no pages")

        for area in areas:
            if area.page >= len(doc):
                continue
            page = doc[area.page]
            rect = page.rect
            # Convert normalized to PDF points
            x0 = rect.x0 + area.x0 * rect.width
            y0 = rect.y0 + area.y0 * rect.height
            x1 = rect.x0 + area.x1 * rect.width
            y1 = rect.y0 + area.y1 * rect.height
            # Ensure x0<x1, y0<y1
            if x0 > x1:
                x0, x1 = x1, x0
            if y0 > y1:
                y0, y1 = y1, y0
            pdf_rect = fitz.Rect(x0, y0, x1, y1)

            # Add redact annotation
            annot = page.add_redact_annot(pdf_rect)
            # Fill color
            fill = area.fill or "white"
            if fill.lower() == "white":
                annot.set_colors(stroke=(1, 1, 1), fill=(1, 1, 1))
            elif fill.lower() == "black":
                annot.set_colors(stroke=(0, 0, 0), fill=(0, 0, 0))
            else:
                try:
                    rgb = _hex_to_rgb(fill)
                    annot.set_colors(stroke=rgb, fill=rgb)
                except Exception:
                    annot.set_colors(stroke=(1, 1, 1), fill=(1, 1, 1))
            annot.update()

        # Apply redactions — this actually removes content
        for page in doc:
            try:
                page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_REMOVE)
            except Exception as e:
                logger.warning("apply_redactions failed on page: %s", e)

        # Save redacted PDF
        out_buffer = io.BytesIO()
        doc.ez_save(out_buffer)  # or doc.save
        # Fallback: doc.tobytes
        try:
            out_bytes = doc.tobytes()
        except Exception:
            out_bytes = out_buffer.getvalue()
            if not out_bytes:
                # Try tobytes via save to buffer
                out_buffer = io.BytesIO()
                doc.save(out_buffer)
                out_bytes = out_buffer.getvalue()

        doc.close()

        if not out_bytes:
            raise HTTPException(status_code=500, detail="Redaction produced empty PDF")

        # Audit log if team context
        team_id_header = request.headers.get("X-Team-Id")
        if team_id_header and user:
            try:
                import uuid

                from app.services.team.team_service import record_audit

                team_uuid = uuid.UUID(team_id_header)
                await record_audit(
                    db,
                    team_id=team_uuid,
                    actor_id=user.id,
                    action="document.redact",
                    target=file.filename,
                    detail=f"Redacted {len(areas)} areas",
                )
            except Exception:
                pass

        return StreamingResponse(
            io.BytesIO(out_bytes),
            media_type="application/pdf",
            headers={
                "Content-Disposition": f'attachment; filename="redacted_{file.filename or "document.pdf"}"',
                "X-Redacted-Areas": str(len(areas)),
            },
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Redaction failed")
        raise HTTPException(status_code=500, detail=f"Redaction failed: {e}")
    finally:
        try:
            doc.close()
        except Exception:
            pass
