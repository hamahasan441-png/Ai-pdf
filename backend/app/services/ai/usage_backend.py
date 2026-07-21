"""Pluggable backends for the free-tier AI usage counter.

The metering contract is intentionally tiny and synchronous so it can be called
from any request path without awaiting:

    allowed, count = backend.check_and_increment(key, limit, day)

``day`` is an ISO date string (the counter resets daily); ``limit`` is the
per-identity cap. When the cap is already reached the counter is NOT incremented
and ``allowed`` is False.

Two implementations ship:

- :class:`InMemoryUsageBackend` — a per-process dict. Correct for a single
  instance / development / tests; resets on restart and is not shared across
  workers.
- :class:`RedisUsageBackend` — an atomic ``INCR`` + daily ``EXPIRE`` keyed
  identically. This is what makes metering correct when the backend runs as
  more than one instance behind a load balancer. It fails *closed to allowing*
  (delegating to an in-memory fallback) if Redis is unreachable, so a Redis
  outage degrades to per-instance metering instead of taking AI down.

:func:`build_backend` picks the implementation from ``settings.AI_METER_BACKEND``.
The Pro-bypass rule lives in ``usage_limiter`` and is unaffected by the backend.
"""

from __future__ import annotations

import logging
from typing import Protocol

logger = logging.getLogger(__name__)


class UsageBackend(Protocol):
    """Minimal metering interface shared by every backend."""

    def check_and_increment(self, key: str, limit: int, day: str) -> tuple[bool, int]:
        """Increment today's counter for ``key``; return ``(allowed, count)``."""
        ...

    def clear(self) -> None:
        """Drop all counters (used by tests)."""
        ...


class InMemoryUsageBackend:
    """Per-process counter. Not shared across instances; resets on restart."""

    def __init__(self) -> None:
        # key -> (day, count)
        self._usage: dict[str, tuple[str, int]] = {}

    def check_and_increment(self, key: str, limit: int, day: str) -> tuple[bool, int]:
        stored_day, count = self._usage.get(key, (day, 0))
        if stored_day != day:
            count = 0
        if count >= limit:
            return False, count
        count += 1
        self._usage[key] = (day, count)
        return True, count

    def clear(self) -> None:
        self._usage.clear()


class RedisUsageBackend:
    """Redis-backed counter for multi-instance deployments.

    Uses a synchronous redis client: the operation is a single ``INCR`` (plus a
    one-time ``EXPIRE``), which is fast and keeps the ``check_and_increment``
    contract synchronous. On any Redis error we transparently fall back to an
    in-memory counter so AI never hard-fails on a cache outage.
    """

    # Keys live slightly longer than a day so a request near midnight UTC still
    # sees a consistent window; the daily key name already scopes the count.
    _TTL_SECONDS = 60 * 60 * 26

    def __init__(self, url: str) -> None:
        import redis  # local import: only needed when Redis is selected

        self._client = redis.Redis.from_url(url, socket_connect_timeout=2, socket_timeout=2)
        self._fallback = InMemoryUsageBackend()
        # Surface connectivity problems once, up front, instead of per request.
        self._client.ping()

    @staticmethod
    def _redis_key(key: str, day: str) -> str:
        return f"ai_usage:{day}:{key}"

    def check_and_increment(self, key: str, limit: int, day: str) -> tuple[bool, int]:
        rkey = self._redis_key(key, day)
        try:
            current = int(self._client.get(rkey) or 0)
            if current >= limit:
                return False, current
            count = int(self._client.incr(rkey))
            if count == 1:
                # First hit of the day for this key: set the daily expiry.
                self._client.expire(rkey, self._TTL_SECONDS)
            return True, count
        except Exception as exc:  # noqa: BLE001 - never let cache break AI
            logger.warning("Redis metering failed (%s); using in-memory fallback", exc)
            return self._fallback.check_and_increment(key, limit, day)

    def clear(self) -> None:
        self._fallback.clear()
        try:
            for rkey in self._client.scan_iter(match="ai_usage:*"):
                self._client.delete(rkey)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Redis metering clear failed: %s", exc)


def build_backend() -> UsageBackend:
    """Construct the metering backend selected by configuration.

    ``memory`` and ``auto`` (when Redis is unavailable) return the in-memory
    backend. ``redis`` / ``auto`` attempt a Redis backend and fall back to
    in-memory if the client cannot be created or reached.
    """
    from app.core.config import settings

    mode = (settings.AI_METER_BACKEND or "auto").strip().lower()

    if mode == "memory":
        return InMemoryUsageBackend()

    if mode in {"redis", "auto"}:
        try:
            return RedisUsageBackend(settings.REDIS_URL)
        except Exception as exc:  # noqa: BLE001 - Redis optional in dev/tests
            if mode == "redis":
                logger.warning(
                    "AI_METER_BACKEND=redis but Redis is unavailable (%s); "
                    "falling back to in-memory metering",
                    exc,
                )
            return InMemoryUsageBackend()

    logger.warning("Unknown AI_METER_BACKEND=%r; using in-memory metering", mode)
    return InMemoryUsageBackend()
