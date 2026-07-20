"""Integration tests for the managed AI chat endpoint (/api/v1/ai/chat)."""

from app.core.config import settings

URL = "/api/v1/ai/chat"


async def test_chat_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]})
    assert resp.status_code == 503


async def test_chat_success_and_metering(client, mock_ai):
    resp = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]})
    assert resp.status_code == 200
    body = resp.json()
    assert body["reply"] == "MOCK_REPLY"
    # One call consumed against the default free limit.
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_chat_rejects_empty_messages(client, mock_ai):
    resp = await client.post(URL, json={"messages": []})
    assert resp.status_code == 422


async def test_chat_429_when_limit_exhausted(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]})
    assert first.status_code == 200
    second = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]})
    assert second.status_code == 429
