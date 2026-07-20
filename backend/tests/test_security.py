"""Unit tests for app.core.security (pure functions, no DB / no network)."""

from datetime import timedelta

import jwt
import pytest

from app.core.config import settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    decrypt_data,
    encrypt_data,
    hash_password,
    verify_password,
)


def test_password_hash_roundtrip():
    hashed = hash_password("s3cret-pass")
    assert hashed != "s3cret-pass"
    assert verify_password("s3cret-pass", hashed) is True
    assert verify_password("wrong", hashed) is False


def test_access_token_claims():
    token = create_access_token(subject="user-123")
    payload = decode_token(token)
    assert payload["sub"] == "user-123"
    assert payload["type"] == "access"


def test_refresh_token_type():
    token = create_refresh_token(subject="user-123")
    payload = decode_token(token)
    assert payload["sub"] == "user-123"
    assert payload["type"] == "refresh"


def test_access_token_extra_claims():
    token = create_access_token(subject="u1", extra_claims={"role": "admin"})
    payload = decode_token(token)
    assert payload["role"] == "admin"


def test_expired_token_raises():
    token = create_access_token(subject="u1", expires_delta=timedelta(seconds=-5))
    with pytest.raises(jwt.ExpiredSignatureError):
        decode_token(token)


def test_tampered_token_raises():
    token = create_access_token(subject="u1")
    with pytest.raises(jwt.InvalidTokenError):
        # Flip the signature by appending junk.
        decode_token(token + "tampered")


def test_wrong_secret_rejected():
    token = jwt.encode({"sub": "x", "type": "access"}, "some-other-secret", algorithm=settings.JWT_ALGORITHM)
    with pytest.raises(jwt.InvalidTokenError):
        decode_token(token)


def test_long_password_over_72_bytes_is_handled():
    # bcrypt only uses the first 72 bytes and newer versions raise on longer
    # input; hashing/verifying a longer password must not raise. (Regression for
    # the "password cannot be longer than 72 bytes" CI failure.)
    long_pw = "p@ssw0rd-" + ("x" * 100)
    hashed = hash_password(long_pw)
    assert verify_password(long_pw, hashed) is True
    assert verify_password("totally-different", hashed) is False


def test_verify_password_handles_malformed_hash():
    # A malformed/empty stored hash must return False, not raise.
    assert verify_password("whatever", "") is False
    assert verify_password("whatever", "not-a-bcrypt-hash") is False


def test_encrypt_decrypt_roundtrip():
    ciphertext = encrypt_data("sensitive value")
    assert ciphertext != "sensitive value"
    assert decrypt_data(ciphertext) == "sensitive value"
