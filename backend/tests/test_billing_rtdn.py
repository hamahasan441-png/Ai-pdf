"""Tests for Play RTDN webhook — Enhancement-Based Masterplan E6.1.

The RTDN endpoint must:
- Accept Pub/Sub push envelope {message:{data: base64_json}}
- Accept raw JSON {purchase_token, product_id, notificationType}
- When verifier not configured, use heuristic to mark invalid on cancel/revoked/expired (3,12,13)
- Persist entitlement so X-Entitlement-Token checks reflect renewal/cancel immediately
- Always return 2xx (Play retries on non-2xx)

These tests run against in-memory SQLite, no network, no real Play creds.
"""

"""Tests for Play RTDN webhook — Enhancement-Based Masterplan E6.1.

The RTDN endpoint must:
- Accept Pub/Sub push envelope {message:{data: base64_json}}
- Accept raw JSON {purchase_token, product_id, notificationType}
- When verifier not configured, use heuristic to mark invalid on cancel/revoked/expired (3,12,13)
- Persist entitlement so X-Entitlement-Token checks reflect renewal/cancel immediately
- Always return 2xx (Play retries on non-2xx)

These tests run against in-memory SQLite, no network, no real Play creds.
"""

import base64
import json

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.entitlement import Entitlement


@pytest.mark.asyncio
async def test_rtdn_ack_no_token(client: AsyncClient):
    """RTDN with no token should ack."""
    resp = await client.post("/api/v1/billing/rtdn", json={"hello": "world"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["received"] is True


@pytest.mark.asyncio
async def test_rtdn_raw_renewed_creates_entitlement(client: AsyncClient, session_maker):
    resp = await client.post(
        "/api/v1/billing/rtdn",
        json={
            "purchase_token": "test_token_rtdn_renewed_123456789012345",
            "product_id": "pro_monthly",
            "notificationType": 2,  # RENEWED
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["received"] is True

    # Entitlement should be persisted — query via fresh session_maker session
    async with session_maker() as session:
        ent = (
            await session.execute(
                select(Entitlement).where(
                    Entitlement.purchase_token == "test_token_rtdn_renewed_123456789012345"
                )
            )
        ).scalar_one_or_none()
        assert ent is not None
        # When verifier not configured, heuristic keeps valid=True for renewed
        assert ent.valid is True


@pytest.mark.asyncio
async def test_rtdn_raw_canceled_marks_invalid(client: AsyncClient, session_maker):
    token = "test_token_rtdn_cancel_1234567890123456"
    # Renewed
    await client.post(
        "/api/v1/billing/rtdn",
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 2},
    )
    # Then canceled (3)
    resp = await client.post(
        "/api/v1/billing/rtdn",
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 3},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["received"] is True

    async with session_maker() as session:
        ent = (
            await session.execute(select(Entitlement).where(Entitlement.purchase_token == token))
        ).scalar_one_or_none()
        assert ent is not None
        assert ent.valid is False
        assert ent.tier == "free"


@pytest.mark.asyncio
async def test_rtdn_pubsub_envelope(client: AsyncClient, session_maker):
    """Pub/Sub envelope: message.data = base64(json(notification))."""
    inner = {
        "subscriptionNotification": {
            "purchaseToken": "test_token_pubsub_123456789012345",
            "subscriptionId": "pro_yearly",
            "notificationType": 2,
        }
    }
    b64 = base64.b64encode(json.dumps(inner).encode()).decode()
    envelope = {"message": {"data": b64, "messageId": "test-msg-1"}}

    resp = await client.post("/api/v1/billing/rtdn", json=envelope)
    assert resp.status_code == 200
    data = resp.json()
    assert data["received"] is True

    async with session_maker() as session:
        ent = (
            await session.execute(
                select(Entitlement).where(
                    Entitlement.purchase_token == "test_token_pubsub_123456789012345"
                )
            )
        ).scalar_one_or_none()
        assert ent is not None


@pytest.mark.asyncio
async def test_rtdn_expired_marks_free(client: AsyncClient, session_maker):
    token = "test_token_rtdn_expired_123456789012345"
    resp = await client.post(
        "/api/v1/billing/rtdn",
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 13},  # EXPIRED
    )
    assert resp.status_code == 200
    async with session_maker() as session:
        ent = (
            await session.execute(select(Entitlement).where(Entitlement.purchase_token == token))
        ).scalar_one_or_none()
        assert ent is not None
        assert ent.valid is False
