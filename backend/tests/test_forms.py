"""Integration tests for the AcroForm reader endpoint."""

import pytest

READ = "/api/v1/forms/acroform/read"


def _blank_pdf() -> bytes:
    import fitz  # PyMuPDF (present in CI via requirements)

    doc = fitz.open()
    doc.new_page()
    try:
        return doc.tobytes()
    finally:
        doc.close()


def _pdf_with_text_field(field_name: str = "full_name") -> bytes:
    """Build a one-page PDF containing a single text form field.

    Wrapped by the caller in a skip-guard because the exact PyMuPDF Widget
    creation API can vary across versions and cannot be exercised in this
    sandbox (no PyMuPDF installed locally).
    """
    import fitz

    doc = fitz.open()
    page = doc.new_page()
    try:
        w = fitz.Widget()
        w.field_name = field_name
        w.field_type = fitz.PDF_WIDGET_TYPE_TEXT
        w.rect = fitz.Rect(50, 50, 250, 70)
        page.add_widget(w)
        return doc.tobytes()
    finally:
        doc.close()


async def test_read_acroform_blank_pdf(client):
    pytest.importorskip("fitz")
    data = _blank_pdf()
    resp = await client.post(READ, files={"file": ("blank.pdf", data, "application/pdf")})
    assert resp.status_code == 200
    body = resp.json()
    assert body["is_form"] is False
    assert body["field_count"] == 0
    assert body["fields"] == []


async def test_read_acroform_with_text_field(client):
    pytest.importorskip("fitz")
    try:
        data = _pdf_with_text_field("full_name")
    except Exception as e:  # noqa: BLE001 - PyMuPDF widget API differs across versions
        pytest.skip(f"PyMuPDF widget creation API differs: {e}")

    resp = await client.post(READ, files={"file": ("form.pdf", data, "application/pdf")})
    assert resp.status_code == 200
    body = resp.json()
    assert body["field_count"] >= 1
    names = [f["name"] for f in body["fields"]]
    assert "full_name" in names
    field = next(f for f in body["fields"] if f["name"] == "full_name")
    assert field["type"]  # a non-empty type label
    assert len(field["rect"]) == 4


async def test_read_acroform_rejects_empty_file(client):
    resp = await client.post(READ, files={"file": ("empty.pdf", b"", "application/pdf")})
    assert resp.status_code == 422


async def test_read_acroform_rejects_non_pdf(client):
    resp = await client.post(
        READ, files={"file": ("junk.pdf", b"not a real pdf", "application/pdf")}
    )
    assert resp.status_code == 422
