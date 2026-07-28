"""Tests for paywall A/B analytics — E6.3A Phase 6."""

import pytest
from httpx import AsyncClient

AUTH = "/api/v1/auth"
PAYWALL = "/api/v1/billing/paywall"
ADMIN = "/api/v1/billing/paywall/stats"


async def _register(client, email="paywall@example.com"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_paywall_exposure_public(client: AsyncClient):
    # Public endpoint, no auth required for anonymous
    resp = await client.post(f"{PAYWALL}/exposure", json={"variant": "A"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["variant"] == "A"
    assert data["event_type"] == "exposure"


@pytest.mark.asyncio
async def test_paywall_conversion_requires_auth(client: AsyncClient):
    # Without auth should 401 or 422 (FastAPI validation when Authorization header missing)
    resp = await client.post(f"{PAYWALL}/conversion", json={"variant": "B", "plan": "yearly"})
    assert resp.status_code in (401, 422)

    token = await _register(client, "paywall_conv@example.com")
    resp2 = await client.post(
        f"{PAYWALL}/conversion",
        headers=_hdr(token),
        json={"variant": "B", "plan": "yearly", "event_type": "conversion"},
    )
    assert resp2.status_code == 200
    assert resp2.json()["variant"] == "B"
    assert resp2.json()["plan"] == "yearly"


@pytest.mark.asyncio
async def test_paywall_trial(client: AsyncClient):
    token = await _register(client, "paywall_trial@example.com")
    resp = await client.post(
        f"{PAYWALL}/trial",
        headers=_hdr(token),
        json={"variant": "A", "plan": "monthly"},
    )
    assert resp.status_code == 200
    assert resp.json()["event_type"] == "trial_start"


@pytest.mark.asyncio
async def test_paywall_admin_stats(client: AsyncClient, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ADMIN_API_TOKEN", "adminsecret")

    # Create some events
    await client.post(f"{PAYWALL}/exposure", json={"variant": "A"})
    await client.post(f"{PAYWALL}/exposure", json={"variant": "A"})
    await client.post(f"{PAYWALL}/exposure", json={"variant": "B"})
    token = await _register(client, "paywall_stats@example.com")
    await client.post(
        f"{PAYWALL}/conversion",
        headers=_hdr(token),
        json={"variant": "A", "plan": "yearly"},
    )

    resp = await client.get(ADMIN, headers={"X-Admin-Token": "adminsecret"})
    assert resp.status_code == 200
    data = resp.json()
    assert "variants" in data
    assert "A" in data["variants"]
    assert data["variants"]["A"]["exposure"] >= 2
    assert "note" in data
