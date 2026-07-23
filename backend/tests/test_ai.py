"""Integration tests for the managed AI chat endpoint (/api/v1/ai/chat)."""

from app.core.config import settings
from app.models.entitlement import Entitlement

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


async def test_chat_pro_entitlement_is_unlimited(client, session_maker, mock_ai, monkeypatch):
    """A Pro token bypasses the free-tier cap entirely."""
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    async with session_maker() as s:
        s.add(
            Entitlement(
                purchase_token="pro-chat-token",
                product_id="pro_monthly",
                tier="monthly",
                valid=True,
            )
        )
        await s.commit()

    headers = {"X-Entitlement-Token": "pro-chat-token"}
    for _ in range(3):
        resp = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]}, headers=headers)
        assert resp.status_code == 200
    assert resp.json()["remaining"] == -1  # UNLIMITED


async def test_chat_basic_tier_uses_higher_limit(client, session_maker, mock_ai, monkeypatch):
    """A 'basic' tier token should honour AI_BASIC_DAILY_LIMIT."""
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    monkeypatch.setattr(settings, "AI_BASIC_DAILY_LIMIT", 5)
    async with session_maker() as s:
        s.add(
            Entitlement(
                purchase_token="basic-chat-token",
                product_id="pro_monthly",
                tier="basic",
                valid=True,
            )
        )
        await s.commit()

    headers = {"X-Entitlement-Token": "basic-chat-token"}
    # Should be allowed past the free limit of 1.
    first = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]}, headers=headers)
    second = await client.post(URL, json={"messages": [{"role": "user", "content": "hi"}]}, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json()["remaining"] != -1  # Not unlimited
