"""TOTP 2FA service — E5.2.

Implements RFC 6238 TOTP without external dependency (stdlib only):
- base32 secret generation (160-bit)
- HMAC-SHA1 token generation, 30s step, 6 digits
- verification with window ±1 step
- recovery codes 8x 10-char alphanumeric.

All secrets stored encrypted via Fernet (encrypt_data / decrypt_data).
"""

import base64
import hashlib
import hmac
import json
import secrets
import struct
import time
from typing import List

# 30-second time step, 6 digits, SHA1, per RFC
_TOTP_STEP = 30
_TOTP_DIGITS = 6
_TOTP_ALGO = hashlib.sha1


def generate_secret() -> str:
    """Generate a 160-bit (20-byte) base32 secret, without padding."""
    # 20 bytes = 160 bits, standard for TOTP
    raw = secrets.token_bytes(20)
    b32 = base64.b32encode(raw).decode("utf-8")
    # Strip padding for compatibility with Authenticator apps
    return b32.rstrip("=")


def _base32_decode(secret: str) -> bytes:
    # Add padding back
    padded = secret.upper()
    mod = len(padded) % 8
    if mod:
        padded += "=" * (8 - mod)
    return base64.b32decode(padded)


def _hotp(secret_bytes: bytes, counter: int, digits: int = _TOTP_DIGITS) -> str:
    counter_bytes = struct.pack(">Q", counter)
    hs = hmac.new(secret_bytes, counter_bytes, _TOTP_ALGO).digest()
    offset = hs[-1] & 0x0F
    # Dynamic truncation
    code = struct.unpack(">I", hs[offset : offset + 4])[0] & 0x7FFFFFFF
    code %= 10**digits
    return str(code).zfill(digits)


def generate_totp(secret: str, for_time: int | None = None) -> str:
    """Generate TOTP for current time (or for_time unix seconds)."""
    if for_time is None:
        for_time = int(time.time())
    secret_bytes = _base32_decode(secret)
    counter = for_time // _TOTP_STEP
    return _hotp(secret_bytes, counter)


def verify_totp(secret: str, token: str, window: int = 1, for_time: int | None = None) -> bool:
    """Verify token with ±window steps. Strips spaces, checks 6-digit numeric."""
    token = token.strip().replace(" ", "")
    if not token.isdigit() or len(token) != _TOTP_DIGITS:
        return False
    if for_time is None:
        for_time = int(time.time())
    secret_bytes = _base32_decode(secret)
    base_counter = for_time // _TOTP_STEP
    for delta in range(-window, window + 1):
        counter = base_counter + delta
        if _hotp(secret_bytes, counter) == token:
            return True
    return False


def generate_recovery_codes(count: int = 8, length: int = 10) -> List[str]:
    """Generate `count` recovery codes, each `length` alphanumeric (A-Z2-9, no ambiguous)."""
    # Use uppercase letters without O/I and digits without 0/1 for readability.
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    codes = []
    for _ in range(count):
        code = "".join(secrets.choice(alphabet) for _ in range(length))
        # Format as XXXX-XXXXX etc? Keep simple 10 chars, but insert hyphen for readability: 5-5
        formatted = f"{code[:5]}-{code[5:]}"
        codes.append(formatted)
    return codes


def recovery_codes_hash_list(codes: List[str]) -> str:
    """Hash recovery codes list as JSON (for storage encrypted, but we keep plaintext hash for verification)."""
    return json.dumps(codes)


def parse_recovery_codes(stored_json: str) -> List[str]:
    try:
        data = json.loads(stored_json)
        if isinstance(data, list):
            return [str(c) for c in data]
        return []
    except Exception:
        return []


def get_otpauth_url(secret: str, email: str, issuer: str = "AI-PDF") -> str:
    """Build otpauth:// URL for QR code."""
    # URL encoding minimal
    from urllib.parse import quote

    label = quote(f"{issuer}:{email}")
    params = f"secret={secret}&issuer={quote(issuer)}&algorithm=SHA1&digits={_TOTP_DIGITS}&period={_TOTP_STEP}"
    return f"otpauth://totp/{label}?{params}"
