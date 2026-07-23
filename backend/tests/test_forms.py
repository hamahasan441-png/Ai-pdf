"""Tests for the AcroForm read + fill endpoints + understand-form AI endpoint."""

import json

import pytest
from app.core.config import settings
from app.models.entitlement import Entitlement

READ = "/api/v1/forms/acroform/read"
FILL = "/api/v1/forms/acroform/fill"
UNDERSTAND = "/api/v1/forms/understand-form"


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


# ---------------------------------------------------------------------------
# understand-form endpoint tests
# ---------------------------------------------------------------------------


async def test_understand_form_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    payload = {"fields": [{"label": "Email", "type_hint": "text", "confidence": 0.3}]}
    resp = await client.post(UNDERSTAND, json=payload)
    assert resp.status_code == 503


async def test_understand_form_success(client, mock_ai, monkeypatch):
    """AI returns field classifications; mock returns {"mock": True, "field": "value"}.

    Because the mock JSON doesn't contain a "fields" key, the endpoint returns an
    empty list from the model result and falls back to returning low-confidence
    "other" entries for every requested label — verifying the fallback path.
    """
    payload = {
        "fields": [
            {"label": "Email-Adresse", "type_hint": "text", "confidence": 0.3},
            {"label": "Geburtsdatum", "type_hint": "date", "confidence": 0.4},
        ],
        "document_context": "German government form",
        "language": "de",
    }
    resp = await client.post(UNDERSTAND, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert "fields" in body
    assert len(body["fields"]) == 2  # fallback fills in for both
    labels = {f["label"] for f in body["fields"]}
    assert "Email-Adresse" in labels
    assert "Geburtsdatum" in labels
    # Fallback: confidence=0.0 and semantic_type="other"
    for f in body["fields"]:
        assert f["semantic_type"] == "other"
        assert f["confidence"] == 0.0


async def test_understand_form_with_valid_ai_response(client, monkeypatch, mock_ai):
    """Simulate a realistic AI JSON response and verify parsing."""
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {
            "fields": [
                {
                    "label": "Email",
                    "semantic_type": "email",
                    "profile_key": "email",
                    "confidence": 0.95,
                    "reason": "Standard email field",
                },
                {
                    "label": "Name",
                    "semantic_type": "full_name",
                    "profile_key": "full_name",
                    "confidence": 0.9,
                    "reason": "Full name field",
                },
            ]
        }

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    payload = {
        "fields": [
            {"label": "Email", "type_hint": "text", "confidence": 0.3},
            {"label": "Name", "type_hint": "text", "confidence": 0.4},
        ]
    }
    resp = await client.post(UNDERSTAND, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    result_map = {f["label"]: f for f in body["fields"]}
    assert result_map["Email"]["semantic_type"] == "email"
    assert result_map["Email"]["profile_key"] == "email"
    assert result_map["Email"]["confidence"] == 0.95
    assert result_map["Name"]["semantic_type"] == "full_name"
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_understand_form_429_when_limit_exceeded(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    payload = {"fields": [{"label": "Telefon", "type_hint": "text", "confidence": 0.2}]}
    first = await client.post(UNDERSTAND, json=payload)
    assert first.status_code == 200
    second = await client.post(UNDERSTAND, json=payload)
    assert second.status_code == 429


async def test_understand_form_pro_is_unlimited(client, session_maker, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    async with session_maker() as s:
        s.add(Entitlement(purchase_token="pro-understand", product_id="pro_lifetime", tier="lifetime", valid=True))
        await s.commit()

    headers = {"X-Entitlement-Token": "pro-understand"}
    payload = {"fields": [{"label": "City", "type_hint": "text", "confidence": 0.3}]}
    for _ in range(3):
        resp = await client.post(UNDERSTAND, json=payload, headers=headers)
        assert resp.status_code == 200
        assert resp.json()["remaining"] == -1


async def test_understand_form_rejects_empty_fields(client, mock_ai):
    """Empty fields list should be rejected by pydantic (min_length=1)."""
    resp = await client.post(UNDERSTAND, json={"fields": []})
    assert resp.status_code == 422


async def test_understand_form_rejects_oversized_fields(client, mock_ai):
    """More than 50 fields should be rejected by pydantic (max_length=50)."""
    payload = {
        "fields": [{"label": f"field{i}", "type_hint": "text", "confidence": 0.1} for i in range(51)]
    }
    resp = await client.post(UNDERSTAND, json=payload)
    assert resp.status_code == 422


async def test_understand_form_drops_hallucinated_labels(client, monkeypatch, mock_ai):
    """Labels returned by the model that were NOT in the request are dropped."""
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {
            "fields": [
                {"label": "RealField", "semantic_type": "email", "profile_key": "email", "confidence": 0.9, "reason": "ok"},
                {"label": "HALLUCINATED", "semantic_type": "phone", "profile_key": "phone", "confidence": 0.8, "reason": "bad"},
            ]
        }

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    payload = {"fields": [{"label": "RealField", "type_hint": "text", "confidence": 0.3}]}
    resp = await client.post(UNDERSTAND, json=payload)
    assert resp.status_code == 200
    labels = [f["label"] for f in resp.json()["fields"]]
    assert "HALLUCINATED" not in labels
    assert "RealField" in labels
