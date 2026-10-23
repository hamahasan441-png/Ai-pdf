"""Tests for the pluggable AI metering backend (5.2 Redis-backed metering).

These exercise the backend contract directly (no HTTP) plus the factory's
selection logic. Redis itself is not required: the ``redis`` selection path is
verified to fall back to in-memory when a server is not reachable, which is the
exact behavior we want in dev/CI.
"""

from app.services.ai.usage_backend import (
    InMemoryUsageBackend,
    build_backend,
)

DAY = "2026-07-20"
NEXT_DAY = "2026-07-21"


def test_in_memory_counts_and_caps():
    b = InMemoryUsageBackend()
    # First two hits allowed under a cap of 3.
    assert b.check_and_increment("u1", 3, DAY) == (True, 1)
    assert b.check_and_increment("u1", 3, DAY) == (True, 2)
    assert b.check_and_increment("u1", 3, DAY) == (True, 3)
    # Cap reached: not allowed and NOT incremented past the cap.
    allowed, count = b.check_and_increment("u1", 3, DAY)
    assert allowed is False
    assert count == 3


def test_in_memory_isolates_keys():
    b = InMemoryUsageBackend()
    b.check_and_increment("u1", 2, DAY)
    # A different identity has its own independent counter.
    assert b.check_and_increment("u2", 2, DAY) == (True, 1)


def test_in_memory_resets_on_new_day():
    b = InMemoryUsageBackend()
    assert b.check_and_increment("u1", 1, DAY) == (True, 1)
    assert b.check_and_increment("u1", 1, DAY)[0] is False
    # New day -> counter resets.
    assert b.check_and_increment("u1", 1, NEXT_DAY) == (True, 1)


def test_clear_wipes_counters():
    b = InMemoryUsageBackend()
    b.check_and_increment("u1", 5, DAY)
    b.clear()
    assert b.check_and_increment("u1", 5, DAY) == (True, 1)


def test_build_backend_memory_mode(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AI_METER_BACKEND", "memory")
    backend = build_backend()
    assert isinstance(backend, InMemoryUsageBackend)


def test_build_backend_redis_unavailable_falls_back(monkeypatch):
    """redis mode with an unreachable server degrades to in-memory."""
    from app.core.config import settings

    monkeypatch.setattr(settings, "AI_METER_BACKEND", "redis")
    # Point at a port nothing is listening on so the ping fails fast.
    monkeypatch.setattr(settings, "REDIS_URL", "redis://127.0.0.1:6390/0")
    backend = build_backend()
    assert isinstance(backend, InMemoryUsageBackend)


def test_build_backend_unknown_mode_falls_back(monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AI_METER_BACKEND", "nonsense")
    assert isinstance(build_backend(), InMemoryUsageBackend)


class _FakeRedis:
    """Minimal Redis stand-in; ``before_incr`` simulates a concurrent request."""

    def __init__(self, start=0, before_incr=None):
        self.value = start
        self.before_incr = before_incr

    def get(self, key):
        return self.value

    def incr(self, key):
        if self.before_incr:
            hook, self.before_incr = self.before_incr, None
            hook(self)
        self.value += 1
        return self.value

    def decr(self, key):
        self.value -= 1
        return self.value

    def expire(self, key, ttl):
        return True


def _redis_backend(fake):
    from app.services.ai.usage_backend import InMemoryUsageBackend, RedisUsageBackend

    b = RedisUsageBackend.__new__(RedisUsageBackend)
    b._client = fake
    b._fallback = InMemoryUsageBackend()
    return b


def test_redis_backend_caps_and_does_not_increment_past_limit():
    fake = _FakeRedis()
    b = _redis_backend(fake)
    assert b.check_and_increment("u1", 2, DAY) == (True, 1)
    assert b.check_and_increment("u1", 2, DAY) == (True, 2)
    assert b.check_and_increment("u1", 2, DAY) == (False, 2)
    assert fake.value == 2


def test_redis_backend_concurrent_increment_cannot_overshoot():
    """A concurrent INCR between check and increment must not let both pass."""
    def concurrent(fake):
        fake.value += 1  # another instance consumed the last slot

    fake = _FakeRedis(start=2, before_incr=concurrent)
    b = _redis_backend(fake)
    allowed, count = b.check_and_increment("u1", 3, DAY)
    assert allowed is False
    assert fake.value == 3
