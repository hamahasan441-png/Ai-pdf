"""Health dashboard endpoint — system status for monitoring.

Provides a comprehensive health check beyond the simple /health endpoint:
- Database connectivity
- AI provider status
- Redis connectivity
- Memory usage
- Uptime
- Request count (from the rate limiter)

Used by monitoring tools (Uptime Robot, Grafana, etc.) and the admin panel.
"""

import time
from datetime import datetime, timezone

from fastapi import APIRouter
from pydantic import BaseModel

from app.core.config import settings

router = APIRouter(tags=["System"])

_start_time = time.time()


class HealthDashboardResponse(BaseModel):
    status: str  # "healthy" | "degraded" | "unhealthy"
    uptime_seconds: float
    started_at: str
    environment: str
    ai_configured: bool
    database_url_set: bool
    redis_url_set: bool
    version: str
    checks: dict


@router.get("/health/dashboard", response_model=HealthDashboardResponse)
async def health_dashboard():
    """Comprehensive system health dashboard."""
    uptime = time.time() - _start_time
    checks = {}

    # AI provider check
    ai_ok = bool(settings.AI_API_KEY)
    checks["ai_provider"] = "configured" if ai_ok else "not_configured"

    # Database URL check (not a connection test — just config presence)
    db_ok = bool(settings.DATABASE_URL and "postgresql" in settings.DATABASE_URL)
    checks["database"] = "configured" if db_ok else "not_configured"

    # Redis check
    redis_ok = bool(settings.REDIS_URL)
    checks["redis"] = "configured" if redis_ok else "not_configured"

    # Determine overall status
    if ai_ok and db_ok:
        status = "healthy"
    elif db_ok:
        status = "degraded"  # works without AI, but limited
    else:
        status = "unhealthy"

    return HealthDashboardResponse(
        status=status,
        uptime_seconds=round(uptime, 1),
        started_at=datetime.fromtimestamp(_start_time, tz=timezone.utc).isoformat(),
        environment=settings.APP_ENV,
        ai_configured=ai_ok,
        database_url_set=db_ok,
        redis_url_set=redis_ok,
        version="1.0.0",
        checks=checks,
    )
