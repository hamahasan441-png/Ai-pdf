"""Performance telemetry ingest + dashboard — E4.6 Phase 6.

Frontend FrameTelemetryService sends slow frames and periodic summaries via
POST /admin/perf/ingest (gated by optional token or public for MVP).
Admin dashboard aggregates p95 per route for performance monitoring.

Endpoints:
- POST /admin/perf/ingest — ingest frame timing event (slow frame or summary)
- GET /admin/perf/stats — aggregates p95 per route, slow rate, ANR risk
- GET /admin/perf/recent — recent slow frames

All gated by ADMIN_API_TOKEN via require_admin_token, but ingest is public for MVP
with best-effort (no auth required for anonymous telemetry, optional auth for logged-in).
"""

from collections import defaultdict, deque
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from app.api.v1.admin import require_admin_token

router = APIRouter(prefix="/admin/perf", tags=["Admin"])

# In-memory store for MVP — replace with Redis/DB for multi-instance
# Each entry: {timestamp, route, pageCount, annotationCount, lowRamMode, p95Ms, slowRate, etc}
_recent_events: deque = deque(maxlen=1000)
_summary_by_route: Dict[str, List[Dict[str, Any]]] = defaultdict(list)


class PerfIngestRequest(BaseModel):
    timestamp: Optional[str] = None
    totalSpanMs: Optional[int] = Field(None, description="Frame total span ms")
    buildDurationMs: Optional[int] = None
    rasterDurationMs: Optional[int] = None
    pageCount: Optional[int] = None
    annotationCount: Optional[int] = None
    lowRamMode: Optional[bool] = None
    route: Optional[str] = Field("/home", description="Current route")
    slow: Optional[bool] = False
    p50Ms: Optional[int] = None
    p95Ms: Optional[int] = None
    p99Ms: Optional[int] = None
    totalFrames: Optional[int] = None
    slowFrames: Optional[int] = None
    slowRate: Optional[float] = None


@router.post("/ingest")
async def ingest_perf(request: Request, body: PerfIngestRequest):
    """Ingest frame timing event (public, best-effort)."""
    event = body.model_dump()
    event["ingest_at"] = datetime.now(timezone.utc).isoformat()
    event["client_ip"] = request.client.host if request.client else "unknown"

    _recent_events.append(event)

    # If summary (has p95), aggregate by route
    route = body.route or "/home"
    if body.p95Ms is not None:
        _summary_by_route[route].append(event)
        # Keep only last 100 per route
        if len(_summary_by_route[route]) > 100:
            _summary_by_route[route] = _summary_by_route[route][-100:]

    return {"received": True, "route": route}


@router.get("/stats", dependencies=[Depends(require_admin_token)])
async def perf_stats():
    """Aggregated p95 per route, slow rate, ANR risk — admin only."""
    stats = {}
    for route, events in _summary_by_route.items():
        if not events:
            continue
        p95s = [e.get("p95Ms", 0) for e in events if e.get("p95Ms") is not None]
        slow_rates = [e.get("slowRate", 0) for e in events if e.get("slowRate") is not None]
        avg_p95 = sum(p95s) / len(p95s) if p95s else 0
        avg_slow = sum(slow_rates) / len(slow_rates) if slow_rates else 0
        stats[route] = {
            "count": len(events),
            "avg_p95_ms": round(avg_p95, 2),
            "max_p95_ms": max(p95s) if p95s else 0,
            "avg_slow_rate": round(avg_slow * 100, 2) if avg_slow else 0,
            "low_ram_count": sum(1 for e in events if e.get("lowRamMode")),
            "last_event": events[-1] if events else None,
        }

    # Overall
    all_p95 = []
    for events in _summary_by_route.values():
        all_p95.extend([e.get("p95Ms", 0) for e in events if e.get("p95Ms") is not None])

    overall_p95 = sum(all_p95) / len(all_p95) if all_p95 else 0

    return {
        "per_route": stats,
        "overall_avg_p95_ms": round(overall_p95, 2),
        "total_events": sum(len(v) for v in _summary_by_route.values()),
        "recent_slow_frames": len([e for e in _recent_events if e.get("slow")]),
        "note": "E4.6 Frame-budget telemetry — p95 per route, slow rate, ANR risk. Frontend FrameTelemetryService sends via addTimingsCallback.",
    }


@router.get("/recent", dependencies=[Depends(require_admin_token)])
async def perf_recent(limit: int = 50):
    """Recent slow frames and summaries — admin only."""
    recent = list(_recent_events)[-limit:]
    return {
        "count": len(recent),
        "events": list(reversed(recent)),
    }


@router.delete("/clear", dependencies=[Depends(require_admin_token)])
async def perf_clear():
    """Clear perf telemetry (admin only)."""
    _recent_events.clear()
    _summary_by_route.clear()
    return {"cleared": True}
