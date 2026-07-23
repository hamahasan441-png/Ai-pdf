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


# ---------------------------------------------------------------------------
# Batch endpoint tests
# ---------------------------------------------------------------------------

BATCH = "/api/v1/forms/batch"


async def test_batch_fills_multiple_forms(client):
    payload = {
        "documents": [
            {"name": "form1.pdf", "fields": [{"label": "email", "type": "email"}]},
            {"name": "form2.pdf", "fields": [{"label": "city", "type": "text"}]},
        ],
        "profile": {"email": "user@example.com", "city": "Berlin"},
    }
    resp = await client.post(BATCH, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["total_forms"] == 2
    assert body["total_filled"] >= 1
    names = [r["doc_name"] for r in body["results"]]
    assert "form1.pdf" in names
    assert "form2.pdf" in names


async def test_batch_empty_documents(client):
    resp = await client.post(BATCH, json={"documents": [], "profile": {}})
    assert resp.status_code == 200
    body = resp.json()
    assert body["total_forms"] == 0
    assert body["results"] == []


async def test_batch_with_field_mappings(client):
    payload = {
        "documents": [
            {"name": "german_form.pdf", "fields": [{"label": "Vorname", "type": "text"}]},
        ],
        "profile": {"first": "Ahmad"},
        "field_mappings": {"Vorname": "first"},
    }
    resp = await client.post(BATCH, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    result = body["results"][0]
    assert result["fields_filled"] == 1
    assert result["filled_values"]["Vorname"] == "Ahmad"


async def test_batch_rejects_oversized_request(client, monkeypatch):
    from app.api.v1 import forms as forms_mod
    monkeypatch.setattr(forms_mod, "_MAX_BATCH_DOCS", 2)
    payload = {
        "documents": [
            {"name": f"form{i}.pdf", "fields": []} for i in range(3)
        ],
        "profile": {},
    }
    resp = await client.post(BATCH, json=payload)
    assert resp.status_code == 422


async def test_batch_validation_errors_returned(client):
    """Validation errors appear in the result (endpoint does not raise 422)."""
    payload = {
        "documents": [
            {"name": "bad.pdf", "fields": [{"label": "email", "type": "email"}]},
        ],
        "profile": {"email": "not-an-email"},
    }
    resp = await client.post(BATCH, json=payload)
    assert resp.status_code == 200
    result = resp.json()["results"][0]
    assert result["validation_errors"] != []

