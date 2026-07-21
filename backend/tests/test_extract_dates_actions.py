"""Tests for extract-dates and extract-actions endpoints."""

from app.core.config import settings

DATES_URL = "/api/v1/document-ai/extract-dates"
ACTIONS_URL = "/api/v1/document-ai/extract-actions"


async def test_extract_dates_success(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {"dates": [
            {"date": "15.08.2026", "description": "Payment due", "type": "due_date", "urgent": True}
        ]}

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(DATES_URL, json={"document_text": "Payment due by 15.08.2026"})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["dates"]) == 1
    assert body["dates"][0]["type"] == "due_date"
    assert body["dates"][0]["urgent"] is True


async def test_extract_dates_503(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(DATES_URL, json={"document_text": "hello"})
    assert resp.status_code == 503


async def test_extract_actions_success(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return {"actions": [
            {"action": "Sign the contract", "assignee": "John", "deadline": "01.09.2026", "priority": "high", "section": "Section 5"}
        ]}

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(ACTIONS_URL, json={"document_text": "John must sign by 01.09.2026"})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["actions"]) == 1
    assert body["actions"][0]["priority"] == "high"
    assert body["actions"][0]["assignee"] == "John"


async def test_extract_actions_503(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(ACTIONS_URL, json={"document_text": "hello"})
    assert resp.status_code == 503
