"""Unit tests for the shared AI usage limiter (mostly pure logic)."""

from types import SimpleNamespace

from app.core.config import settings
from app.services.ai import usage_limiter
from app.services.ai.usage_limiter import (
    UNLIMITED,
    check_and_increment,
    identity_for,
    is_pro,
)


def test_check_and_increment_enforces_limit(monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 3)
    usage_limiter.reset()

    assert check_and_increment("ip:1") == (True, 1)
    assert check_and_increment("ip:1") == (True, 2)
    assert check_and_increment("ip:1") == (True, 3)
    # 4th call is over the cap: not allowed, count unchanged.
    assert check_and_increment("ip:1") == (False, 3)


def test_counters_are_per_identity(monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    usage_limiter.reset()

    assert check_and_increment("a")[0] is True
    # Different identity has its own counter.
    assert check_and_increment("b")[0] is True
    # Same identity again -> blocked.
    assert check_and_increment("a")[0] is False


def test_reset_clears_counters(monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    usage_limiter.reset()
    assert check_and_increment("a")[0] is True
    assert check_and_increment("a")[0] is False
    usage_limiter.reset()
    assert check_and_increment("a")[0] is True


def test_identity_for_uses_user_id_when_present():
    user = SimpleNamespace(id="user-42")
    request = SimpleNamespace(client=SimpleNamespace(host="9.9.9.9"))
    assert identity_for(user, request) == "user-42"


def test_identity_for_falls_back_to_ip():
    request = SimpleNamespace(client=SimpleNamespace(host="1.2.3.4"))
    assert identity_for(None, request) == "1.2.3.4"


def test_identity_for_anonymous_when_no_client():
    request = SimpleNamespace(client=None)
    assert identity_for(None, request) == "anon"


async def test_is_pro_false_without_token():
    # No token -> returns False without touching the DB.
    assert await is_pro(db=None, token=None) is False
    assert await is_pro(db=None, token="") is False


def test_unlimited_sentinel_value():
    assert UNLIMITED == -1
