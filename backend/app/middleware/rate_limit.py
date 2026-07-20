"""Rate Limiting Middleware.

Engineering Decision:
  Rate limiting is essential for a free-tier product to prevent abuse.
  We use a simple in-memory token bucket per user (IP for unauthenticated).

  Limits:
  - Free tier: 20 requests/minute for AI endpoints, 60 for general
  - Upload: 10 files/hour
  - Analysis: 5 documents/hour (expensive AI operations)

  Future: Replace with Redis-backed sliding window for multi-instance.

Why not Redis now:
  - Single instance MVP doesn't need distributed rate limiting
  - In-memory is faster (no network hop)
  - Easy to swap to Redis later (same interface)
"""

import logging
import time
from collections import defaultdict

from fastapi import Request, HTTPException, status

logger = logging.getLogger(__name__)


class RateLimiter:
    """In-memory token bucket rate limiter.

    Thread-safe for single-process async usage.
    Replace with Redis for multi-process deployments.
    """

    def __init__(self):
        self._buckets: dict[str, dict] = defaultdict(lambda: {"tokens": 0, "last_refill": 0.0})

    def _get_key(self, request: Request, endpoint_type: str) -> str:
        """Generate rate limit key from user or IP."""
        # Try to get user ID from auth header (set by auth middleware)
        user_id = getattr(request.state, "user_id", None)
        if user_id:
            return f"user:{user_id}:{endpoint_type}"
        # Fallback to IP
        ip = request.client.host if request.client else "unknown"
        return f"ip:{ip}:{endpoint_type}"

    def check(
        self,
        request: Request,
        endpoint_type: str = "general",
        max_requests: int = 60,
        window_seconds: int = 60,
    ) -> bool:
        """Check if request is within rate limit.

        Args:
            request: FastAPI request
            endpoint_type: Category (general, ai, upload, analyze)
            max_requests: Max requests per window
            window_seconds: Time window in seconds

        Returns:
            True if allowed, raises HTTPException if blocked
        """
        key = self._get_key(request, endpoint_type)
        now = time.time()
        bucket = self._buckets[key]

        # Refill tokens if window has passed
        elapsed = now - bucket["last_refill"]
        if elapsed >= window_seconds:
            bucket["tokens"] = 0
            bucket["last_refill"] = now

        # Check limit
        if bucket["tokens"] >= max_requests:
            logger.warning(f"Rate limit hit: {key} ({bucket['tokens']}/{max_requests})")
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "error": "Rate limit exceeded",
                    "limit": max_requests,
                    "window_seconds": window_seconds,
                    "retry_after": int(window_seconds - elapsed),
                },
            )

        bucket["tokens"] += 1
        return True


# Rate limit configurations for different endpoint types
LIMITS = {
    "general": {"max_requests": 60, "window_seconds": 60},
    "ai": {"max_requests": 20, "window_seconds": 60},
    "upload": {"max_requests": 10, "window_seconds": 3600},
    "analyze": {"max_requests": 5, "window_seconds": 3600},
}

# Singleton
rate_limiter = RateLimiter()
