"""Document Analysis Cache - Avoids re-processing identical documents.

Engineering Decision:
  Many users upload the same form templates repeatedly (visa forms,
  tax forms, insurance forms). Caching the AI analysis result for
  identical documents saves:
  - API costs (no redundant AI calls)
  - Processing time (instant results for cached docs)
  - User experience (immediate feedback)

  Cache key: SHA-256 hash of file content
  Cache value: Pipeline result (fields, type, layout)
  TTL: 7 days (forms don't change often)

  Implementation: In-memory dict for MVP.
  Future: Redis with TTL for multi-instance.

Why SHA-256:
  - Collision-resistant (no false matches)
  - Fast to compute
  - Standard for content addressing
"""

import hashlib
import logging
import time
from typing import Any, Optional

logger = logging.getLogger(__name__)

# Cache TTL: 7 days
CACHE_TTL_SECONDS = 7 * 24 * 3600


class DocumentCache:
    """Caches document analysis results by content hash.

    If the same file (exact bytes) is uploaded again,
    returns cached analysis instantly (no AI call needed).
    """

    def __init__(self):
        self._cache: dict[str, dict[str, Any]] = {}
        self._hits = 0
        self._misses = 0

    def compute_hash(self, file_path: str) -> str:
        """Compute SHA-256 hash of file content."""
        sha256 = hashlib.sha256()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(8192), b""):
                sha256.update(chunk)
        return sha256.hexdigest()

    def get(self, file_hash: str) -> Optional[dict[str, Any]]:
        """Get cached analysis result by file hash.

        Returns None if not cached or expired.
        """
        entry = self._cache.get(file_hash)
        if entry is None:
            self._misses += 1
            return None

        # Check TTL
        if time.time() - entry["cached_at"] > CACHE_TTL_SECONDS:
            del self._cache[file_hash]
            self._misses += 1
            return None

        self._hits += 1
        logger.info(f"Cache HIT: {file_hash[:12]}... (hits={self._hits})")
        return entry["result"]

    def set(self, file_hash: str, result: dict[str, Any]) -> None:
        """Cache an analysis result."""
        self._cache[file_hash] = {
            "result": result,
            "cached_at": time.time(),
        }
        logger.info(f"Cache SET: {file_hash[:12]}... (total={len(self._cache)})")

    def invalidate(self, file_hash: str) -> None:
        """Remove a specific entry from cache."""
        self._cache.pop(file_hash, None)

    def clear(self) -> None:
        """Clear all cached entries."""
        self._cache.clear()

    @property
    def stats(self) -> dict[str, int]:
        """Cache performance statistics."""
        total = self._hits + self._misses
        hit_rate = (self._hits / total * 100) if total > 0 else 0
        return {
            "entries": len(self._cache),
            "hits": self._hits,
            "misses": self._misses,
            "hit_rate_percent": round(hit_rate, 1),
        }


# Singleton
document_cache = DocumentCache()
