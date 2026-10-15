"""PyMuPDF redaction must delete the target text or refuse the whole file."""

import fitz
import pytest

from app.services.pdf.secure_redact import RedactionRejected, redact_pdf_bytes


def _two_lines() -> bytes:
    doc = fitz.open()
    page = doc.new_page(width=300, height=400)
    page.insert_text((30, 40), "SECRET-TOKEN", fontsize=12)
    page.insert_text((30, 300), "PUBLIC-KEEP", fontsize=12)
    data = doc.tobytes()
    doc.close()
    return data


def test_redaction_removes_the_secret_and_keeps_the_other_line():
    original = _two_lines()
    redacted = redact_pdf_bytes(
        original,
        [{"page": 0, "x0": 0.0, "y0": 0.0, "x1": 1.0, "y1": 0.25, "fill": "black"}],
    )
    doc = fitz.open(stream=redacted, filetype="pdf")
    try:
        text = doc[0].get_text()
    finally:
        doc.close()
    assert "SECRET-TOKEN" not in text
    assert "PUBLIC-KEEP" in text
    assert b"SECRET-TOKEN" not in redacted


def test_an_out_of_range_page_rejects_the_whole_request():
    original = _two_lines()
    with pytest.raises(RedactionRejected, match="outside the document"):
        redact_pdf_bytes(
            original,
            [{"page": 4, "x0": 0.0, "y0": 0.0, "x1": 0.5, "y1": 0.2}],
        )


def test_an_empty_rectangle_is_rejected():
    with pytest.raises(RedactionRejected, match="empty"):
        redact_pdf_bytes(
            _two_lines(),
            [{"page": 0, "x0": 0.2, "y0": 0.2, "x1": 0.2, "y1": 0.4}],
        )


def test_a_failed_page_does_not_return_the_original_secret():
    """Invalid PDF bytes never come back as a successful redacted document."""
    with pytest.raises(RedactionRejected):
        redact_pdf_bytes(
            b"not a pdf",
            [{"page": 0, "x0": 0.0, "y0": 0.0, "x1": 0.5, "y1": 0.2}],
        )
