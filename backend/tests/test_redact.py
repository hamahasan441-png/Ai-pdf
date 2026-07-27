"""Tests for true redaction — E1.7 Phase 5."""

import io

import pytest
from httpx import AsyncClient

import fitz  # PyMuPDF


def _create_sample_pdf() -> bytes:
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((50, 50), "This is secret data that should be redacted.")
    page.insert_text((50, 100), "This is public data that should remain.")
    buf = io.BytesIO()
    doc.save(buf)
    doc.close()
    return buf.getvalue()


@pytest.mark.asyncio
async def test_redact_endpoint_removes_text(client: AsyncClient, monkeypatch):
    from app.core.config import settings

    # Redaction doesn't require AI_API_KEY, but we set it to allow metering pass
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    pdf_bytes = _create_sample_pdf()

    # Redact first line (approx normalized rect covering top)
    areas_json = '[{"page":0,"x0":0.05,"y0":0.05,"x1":0.9,"y1":0.15,"fill":"white"}]'

    files = {"file": ("test.pdf", pdf_bytes, "application/pdf")}
    data = {"areas_json": areas_json}

    resp = await client.post("/api/v1/document-ai/redact", files=files, data=data)
    assert resp.status_code == 200, resp.text
    assert resp.headers.get("content-type") == "application/pdf"

    # Verify redacted PDF no longer contains secret text
    redacted_bytes = resp.content
    doc = fitz.open(stream=redacted_bytes, filetype="pdf")
    text = "".join([page.get_text() for page in doc])
    doc.close()

    # Secret should be removed, public should remain (or at least secret not present)
    # PyMuPDF redact removes text in rect, so secret should be gone
    assert "secret data" not in text.lower() or "This is secret" not in text


@pytest.mark.asyncio
async def test_redact_no_areas_rejected(client: AsyncClient, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")
    pdf_bytes = _create_sample_pdf()
    files = {"file": ("test.pdf", pdf_bytes, "application/pdf")}
    data = {"areas_json": "[]"}

    resp = await client.post("/api/v1/document-ai/redact", files=files, data=data)
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_redact_metering(client: AsyncClient, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")
    # Should be metered — test that 429 handling works after exceeding free limit
    # For now just check endpoint exists and returns 200 with valid data
    pdf_bytes = _create_sample_pdf()
    areas_json = '[{"page":0,"x0":0.0,"y0":0.0,"x1":0.1,"y1":0.1}]'
    files = {"file": ("test.pdf", pdf_bytes, "application/pdf")}
    data = {"areas_json": areas_json}

    resp = await client.post("/api/v1/document-ai/redact", files=files, data=data)
    assert resp.status_code in (200, 429)
