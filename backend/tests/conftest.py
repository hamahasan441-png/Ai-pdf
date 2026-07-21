"""Shared pytest fixtures for the backend test suite.

Design notes
------------
- **No real database or network.** Each test gets a fresh in-memory SQLite
  database (via ``aiosqlite``) created within that test's own event loop, which
  avoids the classic "future attached to a different loop" pitfall you get when
  a module-level in-memory engine is shared across function-scoped loops.
- **App is driven in-process** with httpx ``ASGITransport``. That transport does
  NOT run FastAPI lifespan events, so importing the app never triggers the real
  Postgres ``init_db()`` — tests stay hermetic.
- **AI is mocked.** ``ai_provider`` is a singleton; the ``mock_ai`` fixture
  monkeypatches its async methods and sets a fake ``AI_API_KEY`` so endpoints
  pass the "configured" check without making network calls.
- **Metering is isolated.** The in-memory usage counter is reset around every
  test so free-tier limits don't leak between cases.
"""

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import StaticPool

from app.core.config import settings
from app.db.database import Base, get_db
from app.main import app

# Import models so they register on Base.metadata before create_all().
from app.models import document as _document  # noqa: F401
from app.models import entitlement as _entitlement  # noqa: F401
from app.models import team as _team  # noqa: F401
from app.models import user as _user  # noqa: F401
from app.models import api_key as _api_key  # noqa: F401
from app.models import webhook as _webhook  # noqa: F401
from app.models import chat_history as _chat_history  # noqa: F401


@pytest_asyncio.fixture
async def db_engine():
    """A fresh in-memory SQLite engine with all tables, per test."""
    engine = create_async_engine(
        "sqlite+aiosqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    try:
        yield engine
    finally:
        await engine.dispose()


@pytest_asyncio.fixture
async def session_maker(db_engine):
    """Session factory bound to the per-test engine (for direct DB setup)."""
    return async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)


@pytest_asyncio.fixture
async def client(session_maker):
    """HTTP client wired to the app with ``get_db`` overridden to SQLite."""

    async def override_get_db():
        async with session_maker() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()


@pytest.fixture(autouse=True)
def reset_limiter():
    """Reset the free-tier counter around each test and pin the in-memory
    metering backend so the suite never depends on a live Redis server."""
    from app.services.ai import usage_limiter

    original = settings.AI_METER_BACKEND
    settings.AI_METER_BACKEND = "memory"
    usage_limiter.reset()
    yield
    usage_limiter.reset()
    settings.AI_METER_BACKEND = original


@pytest.fixture
def mock_ai(monkeypatch):
    """Patch the AI provider so endpoints never hit the network."""
    from app.services.ai import provider as provider_mod

    async def fake_chat(*args, **kwargs):
        return "MOCK_REPLY"

    async def fake_json(*args, **kwargs):
        return {"mock": True, "field": "value"}

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion", fake_chat)
    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")
    return None
