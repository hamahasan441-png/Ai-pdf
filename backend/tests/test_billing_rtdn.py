"""Tests for Play RTDN webhook — Enhancement-Based Masterplan E6.1.

The RTDN endpoint must:
- Reject unauthenticated / forged Pub/Sub pushes (Google-signed OIDC token with
  the configured audience and service account), and fail closed when push
  authentication is not configured.
- Accept Pub/Sub push envelope {message:{data: base64_json}}
- Accept raw JSON {purchase_token, product_id, notificationType}
- Change an entitlement ONLY from the Play re-verification result — never from
  notificationType alone — and ignore unknown products.
- Persist entitlement so X-Entitlement-Token checks reflect renewal/cancel immediately

These tests run against in-memory SQLite, no network, no real Play creds: the
Google JWKS lookup and the Play verifier are monkeypatched.
"""

import base64
import json
import time

import httpx
import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import AsyncClient
from sqlalchemy import select

from app.core.config import settings
from app.models.entitlement import Entitlement
from app.services.auth import id_token as id_token_mod
from app.services.billing.play_verifier import VerificationResult, play_verifier

URL = "/api/v1/billing/rtdn"
AUDIENCE = "https://api.example.com/api/v1/billing/rtdn"
PUSH_SA = "rtdn-push@example-project.iam.gserviceaccount.com"

_GOOGLE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_ATTACKER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _push_token(*, key=_GOOGLE_KEY, aud=AUDIENCE, email=PUSH_SA, iss="https://accounts.google.com") -> str:
    now = int(time.time())
    claims = {
        "iss": iss,
        "aud": aud,
        "sub": "1234567890",
        "email": email,
        "email_verified": True,
        "iat": now,
        "exp": now + 600,
    }
    return pyjwt.encode(claims, key, algorithm="RS256", headers={"kid": "k1"})


def _auth(**kw) -> dict:
    return {"Authorization": f"Bearer {_push_token(**kw)}"}


class _FakePlay:
    """Stand-in for the Play Developer API, keyed by purchase token."""

    def __init__(self):
        self.results: dict[str, object] = {}
        self.calls: list[tuple] = []

    async def verify(self, product_id, purchase_token, is_subscription):
        self.calls.append((product_id, purchase_token, is_subscription))
        outcome = self.results.get(purchase_token)
        if isinstance(outcome, Exception):
            raise outcome
        if outcome is None:
            return VerificationResult(valid=False, tier="free", expiry_millis=None, raw={})
        return outcome


@pytest.fixture
def play(monkeypatch):
    monkeypatch.setattr(settings, "RTDN_PUSH_AUDIENCE", AUDIENCE)
    monkeypatch.setattr(settings, "RTDN_PUSH_SERVICE_ACCOUNT", PUSH_SA)
    monkeypatch.setattr(settings, "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "{}")
    monkeypatch.setattr(id_token_mod, "_signing_key", lambda url, tok: _GOOGLE_KEY.public_key())
    fake = _FakePlay()
    monkeypatch.setattr(play_verifier, "verify", fake.verify)
    return fake


def _active(tier="monthly"):
    future = int(time.time() * 1000) + 30 * 24 * 3600 * 1000
    return VerificationResult(valid=True, tier=tier, expiry_millis=future, raw={})


def _http_error(code: int) -> httpx.HTTPStatusError:
    req = httpx.Request("GET", "https://androidpublisher.googleapis.com/x")
    return httpx.HTTPStatusError("err", request=req, response=httpx.Response(code, request=req))


async def _get(session_maker, token):
    async with session_maker() as session:
        return (
            await session.execute(select(Entitlement).where(Entitlement.purchase_token == token))
        ).scalar_one_or_none()


@pytest.mark.asyncio
async def test_rtdn_ack_no_token(client: AsyncClient, play):
    """RTDN with no token should ack."""
    resp = await client.post(URL, json={"hello": "world"}, headers=_auth())
    assert resp.status_code == 200
    data = resp.json()
    assert data["received"] is True


@pytest.mark.asyncio
async def test_rtdn_raw_renewed_creates_entitlement(client: AsyncClient, session_maker, play):
    token = "test_token_rtdn_renewed_123456789012345"
    play.results[token] = _active()
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 2},
        headers=_auth(),
    )
    assert resp.status_code == 200
    assert resp.json()["reverified"] is True

    ent = await _get(session_maker, token)
    assert ent is not None
    assert ent.valid is True
    assert ent.expiry_millis is not None  # expiry comes from Play, never None for subs
    assert ent.is_active()


@pytest.mark.asyncio
async def test_rtdn_raw_canceled_marks_invalid(client: AsyncClient, session_maker, play):
    token = "test_token_rtdn_cancel_1234567890123456"
    play.results[token] = _active()
    await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 2},
        headers=_auth(),
    )
    # Play now reports the subscription as no longer entitled.
    play.results[token] = VerificationResult(valid=False, tier="free", expiry_millis=None, raw={})
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 3},
        headers=_auth(),
    )
    assert resp.status_code == 200

    ent = await _get(session_maker, token)
    assert ent is not None
    assert ent.valid is False
    assert ent.tier == "free"


@pytest.mark.asyncio
async def test_rtdn_pubsub_envelope(client: AsyncClient, session_maker, play):
    """Pub/Sub envelope: message.data = base64(json(notification))."""
    token = "test_token_pubsub_123456789012345"
    play.results[token] = _active("yearly")
    inner = {
        "subscriptionNotification": {
            "purchaseToken": token,
            "subscriptionId": "pro_yearly",
            "notificationType": 2,
        }
    }
    b64 = base64.b64encode(json.dumps(inner).encode()).decode()
    envelope = {"message": {"data": b64, "messageId": "test-msg-1"}}

    resp = await client.post(URL, json=envelope, headers=_auth())
    assert resp.status_code == 200
    assert play.calls == [("pro_yearly", token, True)]

    ent = await _get(session_maker, token)
    assert ent is not None
    assert ent.tier == "yearly"


@pytest.mark.asyncio
async def test_rtdn_expired_marks_free(client: AsyncClient, session_maker, play):
    """Play 410 (token gone) is authoritative: entitlement becomes invalid."""
    token = "test_token_rtdn_expired_123456789012345"
    play.results[token] = _http_error(410)
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 13},
        headers=_auth(),
    )
    assert resp.status_code == 200
    ent = await _get(session_maker, token)
    assert ent is not None
    assert ent.valid is False


# --- Security regressions ---------------------------------------------------


@pytest.mark.asyncio
async def test_rtdn_unauthenticated_push_rejected(client: AsyncClient, session_maker, play):
    token = "attacker-chosen-token-123456789"
    play.results[token] = _active()
    resp = await client.post(
        URL, json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 4}
    )
    assert resp.status_code == 401
    assert await _get(session_maker, token) is None
    assert play.calls == []


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "kw, expected",
    [
        ({"key": _ATTACKER_KEY}, 401),
        ({"aud": "https://other.example.com/push"}, 401),
        ({"iss": "https://evil.example.com"}, 401),
        ({"email": "someone-else@evil.iam.gserviceaccount.com"}, 403),
    ],
)
async def test_rtdn_forged_push_rejected(client: AsyncClient, session_maker, play, kw, expected):
    token = "attacker-chosen-token-123456789"
    play.results[token] = _active()
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 4},
        headers=_auth(**kw),
    )
    assert resp.status_code == expected
    assert await _get(session_maker, token) is None


@pytest.mark.asyncio
async def test_rtdn_unconfigured_push_auth_fails_closed(client: AsyncClient, session_maker, play, monkeypatch):
    monkeypatch.setattr(settings, "RTDN_PUSH_AUDIENCE", "")
    token = "test_token_unconfigured_1234567890"
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 4},
        headers=_auth(),
    )
    assert resp.status_code == 503
    assert await _get(session_maker, token) is None


@pytest.mark.asyncio
async def test_rtdn_notification_type_alone_never_grants(client: AsyncClient, session_maker, play):
    """A 'renewed' notification for a token Play does not recognise grants nothing."""
    token = "attacker-chosen-token-123456789"
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "pro_monthly", "notificationType": 2},
        headers=_auth(),
    )
    assert resp.status_code == 200
    ent = await _get(session_maker, token)
    assert ent is None or not ent.is_active()


@pytest.mark.asyncio
async def test_rtdn_does_not_revive_expired_entitlement(client: AsyncClient, session_maker, play):
    async with session_maker() as s:
        s.add(Entitlement(purchase_token="expired-tok", product_id="pro_monthly", tier="monthly",
                          valid=False, expiry_millis=1))
        await s.commit()
    resp = await client.post(
        URL,
        json={"purchaseToken": "expired-tok", "productId": "pro_monthly", "notificationType": 2},
        headers=_auth(),
    )
    assert resp.status_code == 200
    ent = await _get(session_maker, "expired-tok")
    assert not ent.is_active()


@pytest.mark.asyncio
async def test_rtdn_unknown_product_no_change(client: AsyncClient, session_maker, play):
    token = "test_token_unknown_product_123456"
    play.results[token] = _active()
    resp = await client.post(
        URL,
        json={"purchase_token": token, "product_id": "something_else", "notificationType": 4},
        headers=_auth(),
    )
    assert resp.status_code == 200
    assert await _get(session_maker, token) is None
    assert play.calls == []


@pytest.mark.asyncio
async def test_rtdn_without_play_verifier_changes_nothing(client: AsyncClient, session_maker, play, monkeypatch):
    monkeypatch.setattr(settings, "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "")
    async with session_maker() as s:
        s.add(Entitlement(purchase_token="someone-elses-token", product_id="pro_monthly",
                          tier="monthly", valid=True))
        await s.commit()
    resp = await client.post(
        URL,
        json={"purchase_token": "someone-elses-token", "product_id": "pro_monthly", "notificationType": 12},
        headers=_auth(),
    )
    assert resp.status_code == 503
    ent = await _get(session_maker, "someone-elses-token")
    assert ent.valid is True and ent.tier == "monthly"


@pytest.mark.asyncio
async def test_rtdn_play_outage_changes_nothing(client: AsyncClient, session_maker, play):
    async with session_maker() as s:
        s.add(Entitlement(purchase_token="live-token-1234567890", product_id="pro_monthly",
                          tier="monthly", valid=True))
        await s.commit()
    play.results["live-token-1234567890"] = _http_error(500)
    resp = await client.post(
        URL,
        json={"purchase_token": "live-token-1234567890", "product_id": "pro_monthly", "notificationType": 3},
        headers=_auth(),
    )
    assert resp.status_code == 502
    ent = await _get(session_maker, "live-token-1234567890")
    assert ent.valid is True
