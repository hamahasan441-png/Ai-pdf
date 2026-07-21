"""Tests for the suggest-questions endpoint."""

import json

from app.core.config import settings

URL = "/api/v1/document-ai/suggest-questions"


async def test_suggest_questions_success(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    async def fake_chat(*args, **kwargs):
        return json.dumps(["What is the total?", "When is payment due?", "Who signed?"])

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion", fake_chat)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(URL, json={"document_text": "Invoice total 500 EUR due 30 days"})
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["questions"]) == 3
    assert "total" in body["questions"][0].lower()


async def test_suggest_questions_503(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(URL, json={"document_text": "hello"})
    assert resp.status_code == 503


async def test_suggest_questions_metered(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(URL, json={"document_text": "a"})
    assert first.status_code == 200
    second = await client.post(URL, json={"document_text": "b"})
    assert second.status_code == 429
