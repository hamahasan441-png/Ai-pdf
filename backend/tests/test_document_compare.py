"""Tests for the document comparison endpoint."""

from app.core.config import settings

COMPARE = "/api/v1/document-ai/compare"


async def test_compare_success(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {
            "summary": "Section 3 was modified",
            "changes": [
                {"type": "modified", "section": "Section 3", "description": "Amount changed from 500 to 700"}
            ],
        }

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(COMPARE, json={
        "document_a": "Total: 500 EUR. Payment due in 30 days.",
        "document_b": "Total: 700 EUR. Payment due in 15 days.",
    })
    assert resp.status_code == 200
    body = resp.json()
    assert "modified" in body["summary"].lower() or len(body["changes"]) > 0
    assert body["changes"][0]["type"] == "modified"


async def test_compare_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(COMPARE, json={
        "document_a": "hello",
        "document_b": "world",
    })
    assert resp.status_code == 503


async def test_compare_metered(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(COMPARE, json={"document_a": "a", "document_b": "b"})
    assert first.status_code == 200
    second = await client.post(COMPARE, json={"document_a": "a", "document_b": "b"})
    assert second.status_code == 429
