"""Integration tests for the Document AI endpoints and their metering."""

from app.core.config import settings
from app.models.entitlement import Entitlement

SUMMARIZE = "/api/v1/document-ai/summarize"
TRANSLATE = "/api/v1/document-ai/translate"
EXTRACT = "/api/v1/document-ai/extract"
CHAT = "/api/v1/document-ai/chat"
ANALYZE = "/api/v1/document-ai/analyze"
UNDERSTAND_FORM = "/api/v1/document-ai/understand-form"


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


async def test_understand_form_success(client, mock_ai):
    resp = await client.post(
        UNDERSTAND_FORM,
        json={
            "fields": [{"label": "Vorname"}, {"label": "E-Mail", "context": "you@x.com"}],
            "profile_keys": ["first_name", "email"],
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    # The default mock returns no "fields" key -> endpoint yields [] gracefully.
    assert isinstance(body["fields"], list)
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_understand_form_parses_model_fields(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {
            "fields": [
                {
                    "label": "Vorname",
                    "field_type": "name",
                    "profile_key": "first_name",
                    "validation": "none",
                    "confidence": 0.95,
                }
            ]
        }

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    resp = await client.post(
        UNDERSTAND_FORM,
        json={"fields": [{"label": "Vorname"}], "profile_keys": ["first_name"]},
    )
    assert resp.status_code == 200
    fields = resp.json()["fields"]
    assert len(fields) == 1
    assert fields[0]["profile_key"] == "first_name"


async def test_understand_form_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(UNDERSTAND_FORM, json={"fields": [{"label": "x"}]})
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
