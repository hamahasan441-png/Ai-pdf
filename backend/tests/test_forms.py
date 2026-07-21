"""Tests for the AcroForm read + fill endpoints."""

import json

import pytest

READ = "/api/v1/forms/acroform/read"
FILL = "/api/v1/forms/acroform/fill"


def _blank_pdf() -> bytes:
    """A minimal valid PDF with no form fields."""
    import fitz
    doc = fitz.open()
    doc.new_page()
    data = doc.tobytes()
    doc.close()
    return data


def _form_pdf(field_name: str = "full_name") -> bytes:
    """A PDF with one text form field."""
    import fitz
    doc = fitz.open()
    page = doc.new_page()
    w = fitz.Widget()
    w.field_name = field_name
    w.field_type = fitz.PDF_WIDGET_TYPE_TEXT
    w.rect = fitz.Rect(50, 50, 250, 70)
    page.add_widget(w)
    data = doc.tobytes()
    doc.close()
    return data


async def test_read_blank_pdf(client):
    pytest.importorskip("fitz")
    resp = await client.post(READ, files={"file": ("blank.pdf", _blank_pdf(), "application/pdf")})
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_form"] is False
    assert body["field_count"] == 0


async def test_read_form_with_field(client):
    pytest.importorskip("fitz")
    try:
        data = _form_pdf("full_name")
    except Exception as e:
        pytest.skip(f"PyMuPDF widget API differs: {e}")
    resp = await client.post(READ, files={"file": ("form.pdf", data, "application/pdf")})
    assert resp.status_code == 200
    body = resp.json()
    assert body["field_count"] >= 1
    names = [f["name"] for f in body["fields"]]
    assert "full_name" in names


async def test_read_rejects_empty(client):
    resp = await client.post(READ, files={"file": ("x.pdf", b"", "application/pdf")})
    assert resp.status_code == 422


async def test_read_rejects_non_pdf(client):
    resp = await client.post(READ, files={"file": ("x.pdf", b"not a pdf", "application/pdf")})
    assert resp.status_code == 422


async def test_fill_returns_pdf(client):
    pytest.importorskip("fitz")
    try:
        data = _form_pdf("city")
    except Exception as e:
        pytest.skip(f"PyMuPDF widget API differs: {e}")
    values = json.dumps({"city": "Berlin"})
    resp = await client.post(
        FILL,
        files={"file": ("form.pdf", data, "application/pdf")},
        data={"values_json": values},
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"] == "application/pdf"
    assert len(resp.content) > 100  # got a real PDF back


async def test_fill_rejects_invalid_json(client):
    pytest.importorskip("fitz")
    resp = await client.post(
        FILL,
        files={"file": ("x.pdf", _blank_pdf(), "application/pdf")},
        data={"values_json": "not json"},
    )
    assert resp.status_code == 422


async def test_fill_rejects_empty_file(client):
    resp = await client.post(
        FILL,
        files={"file": ("x.pdf", b"", "application/pdf")},
        data={"values_json": "{}"},
    )
    assert resp.status_code == 422
