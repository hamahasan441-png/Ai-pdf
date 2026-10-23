"""AI Document Assistant - FastAPI Application Entry Point."""

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.v1.router import api_router
from app.core.config import settings
from app.middleware.rate_limit import rate_limiter

# Credential / second-factor endpoints that are brute-force targets. Each
# client IP shares one "auth" bucket across all of them.
_AUTH_RATE_LIMITED_PATHS = frozenset(
    {
        "/api/v1/auth/login",
        "/api/v1/auth/login/2fa",
        "/api/v1/auth/2fa/verify",
        "/api/v1/auth/2fa/disable",
    }
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup/shutdown events."""
    # Startup
    print(f"Starting {settings.APP_NAME} in {settings.APP_ENV} mode")
    # Security guard: never boot production with placeholder secrets.
    # (No-op in development.) Raises to prevent an insecure deployment.
    settings.validate_production_secrets()
    # Ensure tables exist (idempotent; skips tables already created by Alembic).
    # Import models so they register on Base.metadata before create_all.
    try:
        from app.db.database import init_db
        from app.models import user as _user  # noqa: F401
        from app.models import document as _document  # noqa: F401
        from app.models import entitlement as _entitlement  # noqa: F401
        from app.models import team as _team  # noqa: F401
        from app.models import api_key as _api_key  # noqa: F401
        from app.models import webhook as _webhook  # noqa: F401
        from app.models import chat_history as _chat_history  # noqa: F401
        from app.models import sync as _sync  # noqa: F401  (E8.2)
        from app.models import collab as _collab  # noqa: F401  (E8.3)
        from app.models import paywall_event as _paywall  # noqa: F401  (E6.3A)

        await init_db()
    except Exception as e:  # noqa: BLE001 - never block boot on DB init
        print(f"[startup] init_db skipped/failed: {e}")
    yield
    # Shutdown
    print("Shutting down application")


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title=settings.APP_NAME,
        description="AI-powered document understanding and form-filling platform",
        version="1.0.0",
        lifespan=lifespan,
        docs_url="/api/docs" if settings.DEBUG else None,
        redoc_url="/api/redoc" if settings.DEBUG else None,
    )

    # CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def auth_rate_limit(request: Request, call_next):
        """Per-IP rate limit on login and 2FA routes (429 when exceeded)."""
        max_requests = settings.AUTH_RATE_LIMIT_MAX_REQUESTS
        if (
            max_requests > 0
            and request.method == "POST"
            and request.url.path.rstrip("/") in _AUTH_RATE_LIMITED_PATHS
        ):
            try:
                rate_limiter.check(
                    request,
                    endpoint_type="auth",
                    max_requests=max_requests,
                    window_seconds=settings.AUTH_RATE_LIMIT_WINDOW_SECONDS,
                )
            except HTTPException as e:
                return JSONResponse(status_code=e.status_code, content={"detail": e.detail})
        return await call_next(request)

    # Include API router
    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health")
    async def health_check():
        return {"status": "healthy", "service": settings.APP_NAME}

    return app


app = create_app()
