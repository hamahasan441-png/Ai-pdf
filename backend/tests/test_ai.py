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


# --- Request limits / tier gating (security regressions) -------------------


def _capture(monkeypatch):
    from app.services.ai import provider as provider_mod

    seen = {}

    async def fake_chat(*args, **kwargs):
        seen.update(kwargs)
        return "MOCK_REPLY"

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion", fake_chat)
    return seen


async def test_chat_free_tier_cannot_use_advanced_model(client, mock_ai, monkeypatch):
    seen = _capture(monkeypatch)
    resp = await client.post(
        URL, json={"messages": [{"role": "user", "content": "hi"}], "use_advanced": True}
    )
    assert resp.status_code == 200
    assert seen["use_advanced"] is False


async def test_chat_paid_tier_can_use_advanced_model(client, session_maker, mock_ai, monkeypatch):
    async with session_maker() as s:
        s.add(Entitlement(purchase_token="adv-token", product_id="pro_monthly", tier="monthly", valid=True))
        await s.commit()
    seen = _capture(monkeypatch)
    resp = await client.post(
        URL,
        json={"messages": [{"role": "user", "content": "hi"}], "use_advanced": True},
        headers={"X-Entitlement-Token": "adv-token"},
    )
    assert resp.status_code == 200
    assert seen["use_advanced"] is True


async def test_chat_temperature_is_clamped(client, mock_ai, monkeypatch):
    seen = _capture(monkeypatch)
    for sent, expected in ((50, 1.5), (-3, 0.0), (0.7, 0.7)):
        resp = await client.post(
            URL, json={"messages": [{"role": "user", "content": "hi"}], "temperature": sent}
        )
        assert resp.status_code == 200
        assert seen["temperature"] == expected


async def test_chat_rejects_oversized_requests(client, mock_ai):
    too_many = [{"role": "user", "content": "hi"}] * 51
    assert (await client.post(URL, json={"messages": too_many})).status_code == 422

    too_long = [{"role": "user", "content": "x" * 50_001}]
    assert (await client.post(URL, json={"messages": too_long})).status_code == 422

    too_much_total = [{"role": "user", "content": "x" * 40_000}] * 3
    assert (await client.post(URL, json={"messages": too_much_total})).status_code == 422
