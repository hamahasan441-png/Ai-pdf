"""Tests for the text-layer extraction endpoint."""

import pytest

URL = "/api/v1/document-ai/text-layer"


def _pdf_with_text() -> bytes:
    import fitz
    doc = fitz.open()
    page = doc.new_page()
    # Insert some text so the text layer has content.
    page.insert_text((72, 72), "Hello World", fontsize=12)
    page.insert_text((72, 100), "Second line", fontsize=10)
    data = doc.tobytes()
    doc.close()
    return data


async def test_extract_text_layer_success(client):
    pytest.importorskip("fitz")
    data = _pdf_with_text()
    resp = await client.post(URL, files={"file": ("test.pdf", data, "application/pdf")})
    assert resp.status_code == 200
    body = resp.json()
    assert body["page_count"] == 1
    assert len(body["elements"]) >= 2
    texts = [e["text"] for e in body["elements"]]
    assert "Hello World" in texts


async def test_extract_text_layer_empty_file(client):
    resp = await client.post(URL, files={"file": ("x.pdf", b"", "application/pdf")})
    assert resp.status_code == 422


async def test_extract_text_layer_non_pdf(client):
    resp = await client.post(URL, files={"file": ("x.pdf", b"not a pdf", "application/pdf")})
    assert resp.status_code == 422
