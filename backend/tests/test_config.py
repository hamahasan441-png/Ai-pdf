"""Unit tests for the production-secrets guard (pure, no DB / no network)."""

import pytest

from app.core.config import Settings


def _settings(**overrides) -> Settings:
    # _env_file=None keeps the test hermetic (ignores any local .env file).
    return Settings(_env_file=None, **overrides)


def test_insecure_defaults_detected():
    s = _settings()
    insecure = s.insecure_defaults()
    assert "SECRET_KEY" in insecure
    assert "JWT_SECRET_KEY" in insecure
    assert "ENCRYPTION_KEY" in insecure


def test_no_insecure_when_overridden():
    s = _settings(
        SECRET_KEY="a" * 32,
        JWT_SECRET_KEY="b" * 32,
        ENCRYPTION_KEY="c" * 32,
    )
    assert s.insecure_defaults() == []


def test_is_production_variants():
    assert _settings(APP_ENV="production").is_production() is True
    assert _settings(APP_ENV="prod").is_production() is True
    assert _settings(APP_ENV="PRODUCTION").is_production() is True
    assert _settings(APP_ENV="development").is_production() is False


def test_dev_allows_default_secrets():
    # Must not raise in development even with placeholder secrets.
    _settings(APP_ENV="development").validate_production_secrets()


def test_production_with_default_secrets_raises():
    s = _settings(APP_ENV="production")
    with pytest.raises(RuntimeError) as exc:
        s.validate_production_secrets()
    # Error should name the offending settings.
    assert "SECRET_KEY" in str(exc.value)


def test_production_with_secure_secrets_ok():
    s = _settings(
        APP_ENV="production",
        SECRET_KEY="x" * 32,
        JWT_SECRET_KEY="y" * 32,
        ENCRYPTION_KEY="z" * 32,
    )
    # No raise when all secrets are overridden.
    s.validate_production_secrets()
