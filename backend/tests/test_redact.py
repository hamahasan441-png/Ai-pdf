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
    areas_json = '[{"page":0,"x0":0.05,"y0":0.04,"x1":0.9,"y1":0.07,"fill":"white"}]'

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

    assert "secret data" not in text.lower()
    assert "public data that should remain" in text
    assert "rendered_fill" in resp.headers.get("x-redaction-verified", "")


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


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "areas_json",
    [
        '[{"page":0,"x0":NaN,"y0":0.05,"x1":0.9,"y1":0.15}]',
        '[{"page":0,"x0":0.1,"y0":0.05,"x1":Infinity,"y1":0.15}]',
        '[{"page":3,"x0":0.1,"y0":0.05,"x1":0.9,"y1":0.15}]',
        '{"page":0}',
        "not json",
    ],
)
async def test_redact_rejects_bad_areas_without_a_pdf(client: AsyncClient, areas_json):
    files = {"file": ("test.pdf", _create_sample_pdf(), "application/pdf")}
    resp = await client.post("/api/v1/document-ai/redact", files=files, data={"areas_json": areas_json})
    assert resp.status_code == 422
    assert resp.headers.get("content-type", "").startswith("application/json")


@pytest.mark.asyncio
async def test_redact_filename_cannot_inject_headers(client: AsyncClient):
    files = {"file": ('../a"b\r\nX-Evil: 1.pdf', _create_sample_pdf(), "application/pdf")}
    areas_json = '[{"page":0,"x0":0.05,"y0":0.05,"x1":0.9,"y1":0.15}]'
    resp = await client.post("/api/v1/document-ai/redact", files=files, data={"areas_json": areas_json})
    assert resp.status_code == 200, resp.text
    disposition = resp.headers["content-disposition"]
    assert disposition.count('"') == 2
    assert "x-evil" not in {k.lower() for k in resp.headers}


@pytest.mark.asyncio
async def test_redact_limits_and_reporting_headers(client: AsyncClient, monkeypatch):
    from app.api.v1 import redact as endpoint
    from app.core.config import settings

    area = '{"page":0,"x0":0.05,"y0":0.04,"x1":0.9,"y1":0.07}'
    pdf = _create_sample_pdf()

    ok = await client.post(
        "/api/v1/document-ai/redact",
        files={"file": ("t.pdf", pdf, "application/pdf")},
        data={"areas_json": f"[{area}]"},
    )
    assert ok.status_code == 200
    assert "metadata=" in ok.headers["x-redaction-hidden-copies-removed"]
    assert ok.headers["x-redaction-occurrences-elsewhere"] == "0"
    assert "hidden_copies" in ok.headers["x-redaction-verified"]

    monkeypatch.setattr(endpoint, "MAX_REDACT_AREAS", 2)
    too_many = await client.post(
        "/api/v1/document-ai/redact",
        files={"file": ("t.pdf", pdf, "application/pdf")},
        data={"areas_json": "[" + ",".join([area] * 3) + "]"},
    )
    assert too_many.status_code == 422

    not_pdf = await client.post(
        "/api/v1/document-ai/redact",
        files={"file": ("t.pdf", b"<html>" + b"x" * 2000, "application/pdf")},
        data={"areas_json": f"[{area}]"},
    )
    assert not_pdf.status_code == 415

    monkeypatch.setattr(settings, "MAX_UPLOAD_SIZE_MB", 0)
    too_big = await client.post(
        "/api/v1/document-ai/redact",
        files={"file": ("t.pdf", pdf, "application/pdf")},
        data={"areas_json": f"[{area}]"},
    )
    assert too_big.status_code == 413
