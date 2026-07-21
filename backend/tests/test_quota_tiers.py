"""Tests for per-plan AI quota tiers (Part 8.1)."""

from app.core.config import settings
from app.services.billing.quota_tiers import (
    quota_for_tier,
    validate_receipt_fields,
)


def test_free_tier_returns_default_limit():
    assert quota_for_tier("free") == settings.AI_FREE_DAILY_LIMIT


def test_basic_tier_returns_basic_limit():
    assert quota_for_tier("basic") == settings.AI_BASIC_DAILY_LIMIT


def test_pro_tiers_are_unlimited():
    assert quota_for_tier("monthly") is None
    assert quota_for_tier("yearly") is None
    assert quota_for_tier("lifetime") is None


def test_unknown_tier_falls_back_to_free():
    assert quota_for_tier("mystery") == settings.AI_FREE_DAILY_LIMIT


def test_validate_receipt_valid():
    errors = validate_receipt_fields("pro_monthly", "a" * 50)
    assert errors == []


def test_validate_receipt_empty_token():
    errors = validate_receipt_fields("pro_monthly", "")
    assert any("too short" in e for e in errors)


def test_validate_receipt_token_too_long():
    errors = validate_receipt_fields("pro_monthly", "x" * 3000)
    assert any("exceeds" in e for e in errors)


def test_validate_receipt_unknown_product():
    errors = validate_receipt_fields("unknown_product", "a" * 50)
    assert any("Unknown product_id" in e for e in errors)


def test_validate_receipt_injection_chars():
    errors = validate_receipt_fields("pro_monthly", "token with <script>")
    assert any("invalid characters" in e for e in errors)


def test_validate_receipt_missing_product():
    errors = validate_receipt_fields("", "a" * 50)
    assert any("required" in e for e in errors)
