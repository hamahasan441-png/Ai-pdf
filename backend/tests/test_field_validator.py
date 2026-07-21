"""Unit tests for the form field value validator (pure logic, no DB/network)."""

from app.services.ai.field_validator import field_validator


def test_email_valid():
    assert field_validator.validate("user@example.com", "email").valid is True


def test_email_invalid():
    r = field_validator.validate("not-an-email", "email")
    assert r.valid is False
    assert "email" in r.error.lower() or "@" in r.error


def test_phone_valid():
    assert field_validator.validate("+49 176 12345678", "phone").valid is True
    assert field_validator.validate("017612345678", "phone").valid is True


def test_phone_too_short():
    assert field_validator.validate("123", "phone").valid is False


def test_date_german_format():
    assert field_validator.validate("15.03.1990", "date").valid is True


def test_date_iso_format():
    assert field_validator.validate("1990-03-15", "date").valid is True


def test_date_invalid():
    r = field_validator.validate("not a date", "date")
    assert r.valid is False


def test_number_valid():
    assert field_validator.validate("1.234,56", "number").valid is True
    assert field_validator.validate("42", "number").valid is True


def test_number_invalid():
    assert field_validator.validate("abc", "number").valid is False


def test_iban_valid():
    # DE test IBAN (passes mod-97)
    assert field_validator.validate("DE89 3704 0044 0532 0130 00", "iban").valid is True


def test_iban_invalid_checksum():
    r = field_validator.validate("DE00 1234 5678 9012 3456 78", "iban")
    assert r.valid is False


def test_iban_too_short():
    assert field_validator.validate("DE89", "iban").valid is False


def test_zip_german():
    assert field_validator.validate("10115", "zip").valid is True


def test_zip_invalid():
    assert field_validator.validate("1", "zip").valid is False


def test_name_valid():
    assert field_validator.validate("Muhammad Ali", "name").valid is True


def test_name_with_digits():
    assert field_validator.validate("John123", "name").valid is False


def test_text_always_valid():
    assert field_validator.validate("anything goes here!!!", "text").valid is True


def test_empty_always_valid():
    assert field_validator.validate("", "email").valid is True
    assert field_validator.validate("  ", "phone").valid is True
