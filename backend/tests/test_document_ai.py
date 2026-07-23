"""Integration tests for the Document AI endpoints and their metering."""

from app.core.config import settings
from app.models.entitlement import Entitlement

SUMMARIZE = "/api/v1/document-ai/summarize"
TRANSLATE = "/api/v1/document-ai/translate"
EXTRACT = "/api/v1/document-ai/extract"
CHAT = "/api/v1/document-ai/chat"
ANALYZE = "/api/v1/document-ai/analyze"
FIX_OCR = "/api/v1/document-ai/fix-ocr"


async def test_summarize_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(SUMMARIZE, json={"document_text": "hello world"})
    assert resp.status_code == 503


async def test_summarize_success(client, mock_ai):
    resp = await client.post(SUMMARIZE, json={"document_text": "hello world", "style": "brief"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["summary"] == "MOCK_REPLY"
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_summarize_large_doc_uses_map_reduce(client, monkeypatch, mock_ai):
    """Documents > _MAP_REDUCE_THRESHOLD chars must go through map-reduce."""
    from app.api.v1 import document_ai as dai_mod
    from app.services.ai import map_reduce_summarizer as mr_mod

    calls: list[str] = []

    async def fake_map_reduce(text, *, chunk_size=3000, style="structured", language="auto"):
        calls.append("map_reduce")
        return "MAP_REDUCE_REPLY"

    monkeypatch.setattr(mr_mod, "map_reduce_summarize", fake_map_reduce)
    # Also make the module-level reference in document_ai point to the patched version.
    monkeypatch.setattr(dai_mod, "map_reduce_summarize", fake_map_reduce)

    big_text = "x" * (dai_mod._MAP_REDUCE_THRESHOLD + 1)
    resp = await client.post(SUMMARIZE, json={"document_text": big_text, "style": "structured"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["summary"] == "MAP_REDUCE_REPLY"
    assert "map_reduce" in calls


async def test_summarize_short_doc_skips_map_reduce(client, monkeypatch, mock_ai):
    """Documents <= _MAP_REDUCE_THRESHOLD chars use the direct AI path."""
    from app.api.v1 import document_ai as dai_mod
    from app.services.ai import map_reduce_summarizer as mr_mod

    calls: list[str] = []

    async def fake_map_reduce(*args, **kwargs):
        calls.append("map_reduce")
        return "SHOULD_NOT_BE_CALLED"

    monkeypatch.setattr(mr_mod, "map_reduce_summarize", fake_map_reduce)
    monkeypatch.setattr(dai_mod, "map_reduce_summarize", fake_map_reduce)

    short_text = "x" * dai_mod._MAP_REDUCE_THRESHOLD  # exactly at threshold → direct path
    resp = await client.post(SUMMARIZE, json={"document_text": short_text})
    assert resp.status_code == 200
    assert resp.json()["summary"] == "MOCK_REPLY"
    assert calls == []  # map-reduce was NOT called


async def test_translate_success(client, mock_ai):
    resp = await client.post(TRANSLATE, json={"text": "hello", "target_language": "Kurdish (Sorani)"})
    assert resp.status_code == 200
    assert resp.json()["translated_text"] == "MOCK_REPLY"


async def test_extract_returns_json(client, mock_ai):
    resp = await client.post(EXTRACT, json={"document_text": "Invoice #42, total 100 USD"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["data"] == {"mock": True, "field": "value"}


async def test_document_chat_success(client, mock_ai):
    resp = await client.post(
        CHAT,
        json={"document_text": "The sky is blue.", "question": "What color is the sky?"},
    )
    assert resp.status_code == 200
    assert resp.json()["answer"] == "MOCK_REPLY"


async def test_analyze_returns_structured_json(client, mock_ai):
    resp = await client.post(ANALYZE, json={"document_text": "Invoice #42, total 100 USD, due 2026-01-01"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["analysis"] == {"mock": True, "field": "value"}
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_analyze_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(ANALYZE, json={"document_text": "hello"})
    assert resp.status_code == 503


async def test_fix_ocr_success(client, mock_ai):
    resp = await client.post(FIX_OCR, json={"text": "He1lo w0rld rn"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["corrected_text"] == "MOCK_REPLY"
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_fix_ocr_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(FIX_OCR, json={"text": "He1lo"})
    assert resp.status_code == 503


async def test_metering_429_across_calls(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(SUMMARIZE, json={"document_text": "a"})
    assert first.status_code == 200
    # Same identity, limit reached -> next Document AI call is blocked.
    second = await client.post(TRANSLATE, json={"text": "a", "target_language": "German"})
    assert second.status_code == 429


async def test_pro_entitlement_is_unlimited(client, session_maker, mock_ai, monkeypatch):
    # Even with a free limit of 1, a verified Pro token bypasses the cap.
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    async with session_maker() as s:
        s.add(
            Entitlement(
                purchase_token="pro-token-xyz",
                product_id="pro_lifetime",
                tier="lifetime",
                valid=True,
            )
        )
        await s.commit()

    headers = {"X-Entitlement-Token": "pro-token-xyz"}
    first = await client.post(SUMMARIZE, json={"document_text": "a"}, headers=headers)
    second = await client.post(SUMMARIZE, json={"document_text": "b"}, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    # Unlimited sentinel.
    assert first.json()["remaining"] == -1
    assert second.json()["remaining"] == -1


async def test_basic_entitlement_uses_higher_limit(client, session_maker, mock_ai, monkeypatch):
    """A 'basic' tier entitlement should give AI_BASIC_DAILY_LIMIT quota."""
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    monkeypatch.setattr(settings, "AI_BASIC_DAILY_LIMIT", 5)
    async with session_maker() as s:
        s.add(
            Entitlement(
                purchase_token="basic-token-abc",
                product_id="pro_monthly",
                # tier is the quota-tier key; product_id is the Play Store SKU.
                # Using an existing valid SKU to satisfy the Entitlement schema;
                # it is the tier field that drives quota resolution.
                tier="basic",
                valid=True,
            )
        )
        await s.commit()

    headers = {"X-Entitlement-Token": "basic-token-abc"}
    # Should succeed up to AI_BASIC_DAILY_LIMIT (5), not hit free limit (1).
    first = await client.post(SUMMARIZE, json={"document_text": "a"}, headers=headers)
    second = await client.post(SUMMARIZE, json={"document_text": "b"}, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    # Still counting — not unlimited.
    assert first.json()["remaining"] != -1


# ---------------------------------------------------------------------------
# understand-form endpoint tests
# ---------------------------------------------------------------------------

UNDERSTAND_FORM = "/api/v1/document-ai/understand-form"


async def test_understand_form_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    payload = {"fields": [{"label": "Vorname", "detected_type": "text", "confidence": 0.4}]}
    resp = await client.post(UNDERSTAND_FORM, json=payload)
    assert resp.status_code == 503


async def test_understand_form_success(client, monkeypatch, mock_ai):
    """Happy path: AI returns a valid field classification list."""
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {
            "language_detected": "German",
            "fields": [
                {
                    "label": "Vorname",
                    "semantic_type": "first_name",
                    "profile_key": "first_name",
                    "field_type": "text",
                    "confidence": 0.98,
                    "reasoning": "German 'Vorname' means first name",
                }
            ],
        }

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)

    payload = {"fields": [{"label": "Vorname", "detected_type": "text", "confidence": 0.4}]}
    resp = await client.post(UNDERSTAND_FORM, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["language_detected"] == "German"
    assert len(body["fields"]) == 1
    field = body["fields"][0]
    assert field["label"] == "Vorname"
    assert field["semantic_type"] == "first_name"
    assert field["profile_key"] == "first_name"
    assert field["field_type"] == "text"
    assert field["confidence"] == 0.98
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_understand_form_fallback_for_omitted_labels(client, monkeypatch, mock_ai):
    """If the AI omits a label, the endpoint inserts an 'unknown' fallback entry."""
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        # AI returns result for only one of two input fields.
        return {
            "language_detected": "German",
            "fields": [
                {
                    "label": "Vorname",
                    "semantic_type": "first_name",
                    "profile_key": "first_name",
                    "field_type": "text",
                    "confidence": 0.98,
                    "reasoning": "German first name",
                }
            ],
        }

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)

    payload = {
        "fields": [
            {"label": "Vorname", "detected_type": "text", "confidence": 0.4},
            {"label": "Obskures Feld", "detected_type": "text", "confidence": 0.1},
        ]
    }
    resp = await client.post(UNDERSTAND_FORM, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    labels = {f["label"] for f in body["fields"]}
    assert "Vorname" in labels
    assert "Obskures Feld" in labels  # fallback entry added
    # Fallback entry should be unknown.
    fallback = next(f for f in body["fields"] if f["label"] == "Obskures Feld")
    assert fallback["semantic_type"] == "unknown"
    assert fallback["confidence"] == 0.0


async def test_understand_form_429_when_limit_reached(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    payload = {"fields": [{"label": "Email", "detected_type": "text", "confidence": 0.3}]}
    first = await client.post(UNDERSTAND_FORM, json=payload)
    assert first.status_code == 200
    second = await client.post(UNDERSTAND_FORM, json=payload)
    assert second.status_code == 429


async def test_understand_form_pro_unlimited(client, session_maker, monkeypatch, mock_ai):
    """Pro entitlement bypasses the daily cap for understand-form."""
    from app.models.entitlement import Entitlement
    from app.services.ai import provider as provider_mod

    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)

    async def fake_json(*args, **kwargs):
        return {"language_detected": "English", "fields": []}

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)

    async with session_maker() as s:
        s.add(Entitlement(
            purchase_token="pro-uf-token",
            product_id="pro_lifetime",
            tier="lifetime",
            valid=True,
        ))
        await s.commit()

    headers = {"X-Entitlement-Token": "pro-uf-token"}
    payload = {"fields": [{"label": "Name", "detected_type": "text", "confidence": 0.3}]}
    first = await client.post(UNDERSTAND_FORM, json=payload, headers=headers)
    second = await client.post(UNDERSTAND_FORM, json=payload, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["remaining"] == -1


async def test_understand_form_empty_fields_rejected(client, mock_ai):
    """An empty fields list is rejected with 422."""
    resp = await client.post(UNDERSTAND_FORM, json={"fields": []})
    assert resp.status_code == 422


async def test_understand_form_too_many_fields_rejected(client, mock_ai):
    """More than 50 fields per call is rejected with 422."""
    fields = [{"label": f"Field {i}", "detected_type": "text", "confidence": 0.5} for i in range(51)]
    resp = await client.post(UNDERSTAND_FORM, json={"fields": fields})
    assert resp.status_code == 422


async def test_understand_form_malformed_ai_response(client, monkeypatch, mock_ai):
    """Malformed AI response (not the expected shape) is handled gracefully."""
    from app.services.ai import provider as provider_mod

    async def fake_json_bad(*args, **kwargs):
        # AI returns something unexpected.
        return {"nonsense": 42}

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json_bad)

    payload = {"fields": [{"label": "Geburtsdatum", "detected_type": "date", "confidence": 0.2}]}
    resp = await client.post(UNDERSTAND_FORM, json=payload)
    assert resp.status_code == 200
    body = resp.json()
    # All input labels should appear as unknown fallbacks.
    assert len(body["fields"]) == 1
    assert body["fields"][0]["semantic_type"] == "unknown"
