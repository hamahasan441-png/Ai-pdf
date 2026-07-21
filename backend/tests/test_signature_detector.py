"""Tests for the AI signature detector."""

from app.services.ai.signature_detector import signature_detector


def test_detect_german_signature_label():
    lines = [
        {"text": "Ort, Datum, Unterschrift", "x": 0.1, "y": 0.8, "w": 0.4, "h": 0.02},
    ]
    results = signature_detector.detect_from_ocr_lines(lines)
    assert len(results) == 1
    assert results[0]["confidence"] >= 0.9
    assert results[0]["type"] == "signature"


def test_detect_english_signature():
    lines = [
        {"text": "Authorized Signature: _______________", "x": 0.1, "y": 0.9, "w": 0.5, "h": 0.02},
    ]
    results = signature_detector.detect_from_ocr_lines(lines)
    assert len(results) == 1
    assert results[0]["confidence"] >= 0.7


def test_detect_underline_pattern():
    lines = [
        {"text": "________________________", "x": 0.3, "y": 0.85, "w": 0.4, "h": 0.01},
    ]
    results = signature_detector.detect_from_ocr_lines(lines)
    assert len(results) == 1
    assert results[0]["confidence"] >= 0.7


def test_no_signature_in_normal_text():
    lines = [
        {"text": "This is a normal paragraph about payments.", "x": 0.1, "y": 0.3, "w": 0.8, "h": 0.02},
    ]
    results = signature_detector.detect_from_ocr_lines(lines)
    assert len(results) == 0


def test_kurdish_signature_label():
    lines = [
        {"text": "واژۆ", "x": 0.5, "y": 0.9, "w": 0.15, "h": 0.02},
    ]
    results = signature_detector.detect_from_ocr_lines(lines)
    assert len(results) == 1


def test_is_signature_label():
    assert signature_detector.is_signature_label("Unterschrift") is True
    assert signature_detector.is_signature_label("واژۆ") is True
    assert signature_detector.is_signature_label("Total amount") is False
