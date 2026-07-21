"""Tests for the document outline endpoint."""

import json

from app.core.config import settings

URL = "/api/v1/document-ai/outline"


async def test_outline_from_text_success(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    async def fake_chat(*args, **kwargs):
        return json.dumps([
            {"title": "Introduction", "page": 0, "level": 1, "children": []},
            {"title": "Methods", "page": 2, "level": 1, "children": []},
        ])

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion", fake_chat)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(URL, data={"document_text": "Introduction... Methods... Results..."})
    assert resp.status_code == 200
    body = resp.json()
    assert body["source"] == "ai"
    assert len(body["items"]) == 2
    assert body["items"][0]["title"] == "Introduction"


async def test_outline_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(URL, data={"document_text": "hello"})
    assert resp.status_code == 503


async def test_outline_422_no_content(client, mock_ai):
    resp = await client.post(URL)
    assert resp.status_code == 422
