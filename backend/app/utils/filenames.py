"""Filename helpers for uploads, audit entries and download headers."""

from pathlib import PurePath
from typing import Optional
from urllib.parse import quote


def safe_filename(name: Optional[str], default: str = "document.pdf") -> str:
    """ASCII-only name for headers, audit logs and disk; drops quotes and paths."""
    base = (name or "").replace("\\", "/").rsplit("/", 1)[-1]
    cleaned = "".join(ch for ch in base if ch.isascii() and (ch.isalnum() or ch in "._- "))
    cleaned = cleaned.strip(" .")[:120]
    return cleaned or default


def content_disposition(filename: str) -> str:
    """``attachment`` header value that survives any (e.g. Arabic) filename.

    Starlette encodes headers as latin-1, so the plain ``filename`` parameter
    carries an ASCII fallback and the real name goes in RFC 5987
    ``filename*=UTF-8''...`` (percent-encoded, so no quotes / CR / LF).
    """
    base = (filename or "").replace("\\", "/").rsplit("/", 1)[-1]
    path = PurePath(base)
    stem = safe_filename(path.stem, default="document")
    ext = safe_filename(path.suffix, default="")
    fallback = f"{stem}.{ext}" if ext else stem
    encoded = quote(base or fallback, safe="")
    return f"attachment; filename=\"{fallback}\"; filename*=UTF-8''{encoded}"
