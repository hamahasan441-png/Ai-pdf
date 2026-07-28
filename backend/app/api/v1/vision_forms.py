"""Vision Forms detection — E2.7 Enhancement-Based Masterplan (Phase 5).

When OCR field detection confidence is low, crop field rect as image and send to
vision model (AI_VISION_MODELS) for better detection of checkboxes, handwritten fields, etc.

Flow (hybrid):
1. Heuristics first (instant, offline) via ocr_field_detection_service.dart
2. When confidence < threshold, server crops field rect as image → POST /forms/vision-detect
   with {label, image_base64, detected_type, confidence, language}
3. Vision model classifies field type + semantic mapping, improves recall 20%
4. Returns same schema as /understand-form but with vision confidence boost

This endpoint supports both single and batch vision detection.

Uses AI_VISION_MODELS list from config (must support image input) with fallback to AI_MODEL_ADVANCED.
"""

import base64
import logging
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps.auth import get_optional_user
from app.core.config import settings
from app.db.database import get_db
from app.models.user import User
from app.services.ai.provider import ai_provider
from app.services.ai.usage_limiter import UNLIMITED, check_and_increment_tiered, identity_for
from app.services.billing.quota_tiers import get_quota, get_quota_with_team

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/forms", tags=["Forms"])


class VisionFieldInput(BaseModel):
    label: str = Field(..., max_length=500, description="Field label as detected")
    image_base64: Optional[str] = Field(None, description="Base64 JPEG/PNG crop of field rect (optional, improves vision)")
    image_mime: str = Field("image/jpeg", description="MIME type of image")
    detected_type: str = Field("text", description="Heuristic type hint")
    confidence: float = Field(0.5, ge=0.0, le=1.0)
    language: str = Field("auto")


class VisionFieldResult(BaseModel):
    label: str
    semantic_type: str
    profile_key: str
    field_type: str
    confidence: float
    vision_confidence: float
    reasoning: str = ""


class VisionDetectRequest(BaseModel):
    fields: List[VisionFieldInput] = Field(..., min_length=1, max_length=20, description="Fields with optional image crops (max 20)")
    language: str = Field("auto")


class VisionDetectResponse(BaseModel):
    fields: List[VisionFieldResult]
    model_used: str
    remaining: int = -1


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
            tier, limit = await get_quota(db, token)
            source = "entitlement" if token else "free"
    else:
        tier, limit = await get_quota(db, token)
        source = "entitlement" if token else "free"

    if limit is None:
        return UNLIMITED

    identity = f"team:{team_id_header}" if source == "team" and team_id_header else identity_for(user, request)
    allowed, count = check_and_increment_tiered(identity, limit)
    if not allowed:
        raise HTTPException(status_code=429, detail="Daily AI limit reached")
    return max(0, limit - count)


def _check_ai():
    if not settings.AI_API_KEY:
        raise HTTPException(status_code=503, detail="AI not configured")


@router.post("/vision-detect", response_model=VisionDetectResponse)
async def vision_detect(
    req: VisionDetectRequest,
    request: Request,
    user: Optional[User] = Depends(get_optional_user),
    db: AsyncSession = Depends(get_db),
):
    """Vision-based form field detection — uses vision model for low-confidence fields (E2.7)."""
    _check_ai()
    remaining = await _meter(request, user, db)

    # Build messages for vision model
    # System prompt
    messages = [
        {
            "role": "system",
            "content": (
                "You are a form field vision expert. Given field label crops (images) and heuristic hints, "
                "classify each field precisely. For each input field, return semantic_type (snake_case e.g. first_name, email, checkbox), "
                "profile_key (same as semantic_type), field_type (text|date|email|phone|number|checkbox|radio|signature|address|select), "
                "confidence 0..1, vision_confidence 0..1 (how much vision helped), and reasoning (one sentence). "
                f"Form language hint: {req.language}. Respond with valid JSON: {{\"fields\": [...]}} only."
            ),
        }
    ]

    # User content with images
    content_parts = []
    fields_desc = []
    for i, f in enumerate(req.fields):
        desc = f"Field {i+1}: label='{f.label}' detected_type={f.detected_type} heuristic_confidence={f.confidence}"
        fields_desc.append(desc)
        content_parts.append({"type": "text", "text": desc})
        if f.image_base64:
            # Validate base64
            try:
                # Strip data URL prefix if present
                b64 = f.image_base64
                if b64.startswith("data:"):
                    b64 = b64.split(",", 1)[1] if "," in b64 else b64
                # Try decode to validate
                base64.b64decode(b64[:100])
                content_parts.append(
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:{f.image_mime};base64,{b64}"},
                    }
                )
            except Exception:
                # Invalid base64, skip image
                pass

    fields_desc_text = "\n".join(fields_desc)
    content_parts.insert(0, {"type": "text", "text": f"Classify these fields:\n{fields_desc_text}"})

    messages.append({"role": "user", "content": content_parts})

    # Try vision models first, fallback to advanced
    model_used = settings.AI_VISION_MODELS[0] if settings.AI_VISION_MODELS else settings.AI_MODEL
    try:
        result = await ai_provider.chat_completion_json(
            messages=messages,
            use_advanced=False,
            max_tokens=2048,
            model_override=model_used,
        )
    except Exception as e:
        logger.warning("Vision model %s failed, fallback to advanced: %s", model_used, e)
        model_used = settings.AI_MODEL_ADVANCED
        result = await ai_provider.chat_completion_json(
            messages=messages,
            use_advanced=True,
            max_tokens=2048,
        )

    raw_fields = result.get("fields", []) if isinstance(result, dict) else []
    classified = []
    for item in raw_fields:
        if not isinstance(item, dict):
            continue
        label = item.get("label", "")
        if not label:
            continue
        # Find matching input to preserve original label if needed
        classified.append(
            VisionFieldResult(
                label=label,
                semantic_type=str(item.get("semantic_type", "unknown"))[:100],
                profile_key=str(item.get("profile_key", item.get("semantic_type", "unknown")))[:100],
                field_type=str(item.get("field_type", "text"))[:50],
                confidence=float(item.get("confidence", 0.5)),
                vision_confidence=float(item.get("vision_confidence", item.get("confidence", 0.5))),
                reasoning=str(item.get("reasoning", ""))[:300],
            )
        )

    # Fallback for omitted labels
    returned = {r.label for r in classified}
    for f in req.fields:
        if f.label not in returned:
            classified.append(
                VisionFieldResult(
                    label=f.label,
                    semantic_type="unknown",
                    profile_key="unknown",
                    field_type=f.detected_type,
                    confidence=0.0,
                    vision_confidence=0.0,
                    reasoning="Not classified by vision",
                )
            )

    return VisionDetectResponse(fields=classified, model_used=model_used, remaining=remaining)
