"""AI Document Assistant - FastAPI Application Entry Point."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler for startup/shutdown events."""
    # Startup
    print(f"Starting {settings.APP_NAME} in {settings.APP_ENV} mode")
    # Ensure tables exist (idempotent; skips tables already created by Alembic).
    # Import models so they register on Base.metadata before create_all.
    try:
        from app.db.database import init_db
        from app.models import user as _user  # noqa: F401
        from app.models import document as _document  # noqa: F401
        from app.models import entitlement as _entitlement  # noqa: F401

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

    # Include API router
    app.include_router(api_router, prefix="/api/v1")

    @app.get("/health")
    async def health_check():
        return {"status": "healthy", "service": settings.APP_NAME}

    return app


app = create_app()
