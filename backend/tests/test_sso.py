"""Tests for SSO OIDC — E5.3 Enhancement-Based Masterplan.

ID tokens are signed with a throwaway RSA key whose public half is served by
monkeypatching ``id_token._signing_key`` (the only JWKS network touchpoint),
so the real signature / aud / iss checks run without network access.
"""

import time

import jwt as pyjwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import AsyncClient

from app.core.config import settings
from app.services.auth import id_token as id_token_mod

GOOGLE_CLIENT_ID = "test-google-client.apps.googleusercontent.com"
APPLE_CLIENT_ID = "com.example.app"
OIDC_ISSUER = "https://example.okta.com"
OIDC_CLIENT_ID = "okta-client"

_PROVIDER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_ATTACKER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


@pytest.fixture(autouse=True)
def sso_configured(monkeypatch):
    """Configure all three providers and serve the test key as their JWKS."""
    monkeypatch.setattr(settings, "GOOGLE_OAUTH_CLIENT_IDS", [GOOGLE_CLIENT_ID])
    monkeypatch.setattr(settings, "APPLE_CLIENT_IDS", [APPLE_CLIENT_ID])
    monkeypatch.setattr(settings, "OIDC_ISSUER", OIDC_ISSUER)
    monkeypatch.setattr(settings, "OIDC_JWKS_URI", "https://example.okta.com/keys")
    monkeypatch.setattr(settings, "OIDC_CLIENT_IDS", [OIDC_CLIENT_ID])
    monkeypatch.setattr(
        id_token_mod, "_signing_key", lambda jwks_url, token: _PROVIDER_KEY.public_key()
    )


def _make_id_token(payload: dict, *, key=_PROVIDER_KEY, aud=GOOGLE_CLIENT_ID) -> str:
    now = int(time.time())
    claims = {"iat": now, "exp": now + 600, "aud": aud}
    claims.update(payload)
    return pyjwt.encode(claims, key, algorithm="RS256", headers={"kid": "test-kid"})


@pytest.mark.asyncio
async def test_google_sso_create_user(client: AsyncClient, monkeypatch):
    payload = {
        "email": "sso_google@example.com",
        "email_verified": True,
        "name": "SSO Google",
        "sub": "google-123",
        "iss": "https://accounts.google.com",
    }
    id_token = _make_id_token(payload)

    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": id_token})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert "access_token" in data

    # Login again with same email via SSO should return same user (not duplicate)
    resp2 = await client.post("/api/v1/auth/sso/google", json={"id_token": id_token})
    assert resp2.status_code == 200


@pytest.mark.asyncio
async def test_google_sso_missing_email_rejected(client: AsyncClient):
    payload = {"sub": "no-email", "iss": "https://accounts.google.com"}
    id_token = _make_id_token(payload)
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": id_token})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_apple_sso(client: AsyncClient):
    payload = {
        "sub": "apple-123",
        "email": "sso_apple@example.com",
        "email_verified": "true",
        "iss": "https://appleid.apple.com",
    }
    id_token = _make_id_token(payload, aud=APPLE_CLIENT_ID)
    resp = await client.post(
        "/api/v1/auth/sso/apple",
        json={"id_token": id_token, "email": "sso_apple@example.com", "full_name": "Apple User"},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_generic_oidc_sso(client: AsyncClient):
    issuer = OIDC_ISSUER
    payload = {
        "email": "oidc@example.com",
        "email_verified": True,
        "sub": "oidc-123",
        "iss": issuer,
        "name": "OIDC User",
    }
    id_token = _make_id_token(payload, aud=OIDC_CLIENT_ID)
    resp = await client.post(
        "/api/v1/auth/sso/oidc", json={"id_token": id_token, "issuer": issuer}
    )
    assert resp.status_code == 200

    # Wrong issuer -> 422
    resp_bad = await client.post(
        "/api/v1/auth/sso/oidc", json={"id_token": id_token, "issuer": "https://other.com"}
    )
    assert resp_bad.status_code == 422


@pytest.mark.asyncio
async def test_sso_team_enforcement(client: AsyncClient):
    # Create owner and member via SSO and normal register
    # Owner registers normal
    owner_resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "sso_team_owner@example.com", "password": "password123", "full_name": "Owner"},
    )
    owner_token = owner_resp.json()["access_token"]

    # Member normal (not verified)
    member_resp = await client.post(
        "/api/v1/auth/register",
        json={"email": "sso_team_member@example.com", "password": "password123", "full_name": "Member"},
    )

    # Owner creates team
    team_resp = await client.post(
        "/api/v1/teams", headers={"Authorization": f"Bearer {owner_token}"}, json={"name": "SSO Team"}
    )
    team_id = team_resp.json()["id"]

    # Enable SSO required
    quota_resp = await client.put(
        f"/api/v1/teams/{team_id}/quota",
        headers={"Authorization": f"Bearer {owner_token}"},
        json={"sso_required": True},
    )
    assert quota_resp.status_code == 200
    assert quota_resp.json()["sso_required"] is True

    # Try add member who is not verified (normal register is_verified=False) -> should fail 403
    add_bad = await client.post(
        f"/api/v1/teams/{team_id}/members",
        headers={"Authorization": f"Bearer {owner_token}"},
        json={"email": "sso_team_member@example.com", "role": "member"},
    )
    assert add_bad.status_code in (401, 403)

    # Now make member SSO verified (login via SSO with same email)
    payload = {
        "email": "sso_team_member@example.com",
        "email_verified": True,
        "name": "Member SSO",
        "sub": "google-member",
        "iss": "https://accounts.google.com",
    }
    id_token = _make_id_token(payload)
    sso_resp = await client.post("/api/v1/auth/sso/google", json={"id_token": id_token})
    assert sso_resp.status_code == 200

    # Now add should succeed (member is now verified)
    add_good = await client.post(
        f"/api/v1/teams/{team_id}/members",
        headers={"Authorization": f"Bearer {owner_token}"},
        json={"email": "sso_team_member@example.com", "role": "member"},
    )
    assert add_good.status_code == 201, add_good.text


# --- Verification regressions (forged / misconfigured / wrong claims) -------

_GOOGLE_CLAIMS = {
    "email": "victim@example.com",
    "email_verified": True,
    "sub": "google-victim",
    "iss": "https://accounts.google.com",
}


@pytest.mark.asyncio
async def test_google_sso_rejects_token_signed_with_other_key(client: AsyncClient):
    forged = _make_id_token(_GOOGLE_CLAIMS, key=_ATTACKER_KEY)
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": forged})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_google_sso_rejects_hmac_and_unsigned_tokens(client: AsyncClient):
    hs = pyjwt.encode(dict(_GOOGLE_CLAIMS, aud=GOOGLE_CLIENT_ID), "attacker-key", algorithm="HS256")
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": hs})
    assert resp.status_code == 401

    unsigned = pyjwt.encode(dict(_GOOGLE_CLAIMS, aud=GOOGLE_CLIENT_ID), None, algorithm="none")
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": unsigned})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_google_sso_forged_token_cannot_take_over_account(client: AsyncClient):
    reg = await client.post(
        "/api/v1/auth/register",
        json={"email": "victim@example.com", "password": "password123", "full_name": "Victim"},
    )
    assert reg.status_code == 201
    forged = _make_id_token(_GOOGLE_CLAIMS, key=_ATTACKER_KEY)
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": forged})
    assert resp.status_code == 401
    assert "access_token" not in resp.text


@pytest.mark.asyncio
async def test_google_sso_rejects_wrong_audience(client: AsyncClient):
    token = _make_id_token(_GOOGLE_CLAIMS, aud="some-other-app")
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": token})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_google_sso_rejects_wrong_issuer(client: AsyncClient):
    token = _make_id_token(dict(_GOOGLE_CLAIMS, iss="https://evil.example.com"))
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": token})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_google_sso_rejects_expired_token(client: AsyncClient):
    token = _make_id_token(dict(_GOOGLE_CLAIMS, iat=1, exp=2))
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": token})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_google_sso_rejects_unverified_email(client: AsyncClient):
    token = _make_id_token(dict(_GOOGLE_CLAIMS, email_verified=False))
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": token})
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_sso_unconfigured_provider_fails_closed(client: AsyncClient, monkeypatch):
    monkeypatch.setattr(settings, "GOOGLE_OAUTH_CLIENT_IDS", [])
    monkeypatch.setattr(settings, "APPLE_CLIENT_IDS", [])
    monkeypatch.setattr(settings, "OIDC_ISSUER", "")
    google = _make_id_token(_GOOGLE_CLAIMS)
    resp = await client.post("/api/v1/auth/sso/google", json={"id_token": google})
    assert resp.status_code == 503

    apple = _make_id_token(
        {"sub": "a", "email": "a@example.com", "email_verified": "true", "iss": "https://appleid.apple.com"},
        aud=APPLE_CLIENT_ID,
    )
    resp = await client.post("/api/v1/auth/sso/apple", json={"id_token": apple})
    assert resp.status_code == 503

    oidc = _make_id_token(
        {"sub": "o", "email": "o@example.com", "email_verified": True, "iss": OIDC_ISSUER},
        aud=OIDC_CLIENT_ID,
    )
    resp = await client.post("/api/v1/auth/sso/oidc", json={"id_token": oidc, "issuer": OIDC_ISSUER})
    assert resp.status_code == 503


@pytest.mark.asyncio
async def test_apple_sso_ignores_body_email(client: AsyncClient):
    """Apple: an email in the request body must never select the account."""
    await client.post(
        "/api/v1/auth/register",
        json={"email": "apple_victim@example.com", "password": "password123", "full_name": "Victim"},
    )
    token = _make_id_token(
        {"sub": "apple-attacker", "iss": "https://appleid.apple.com"}, aud=APPLE_CLIENT_ID
    )
    resp = await client.post(
        "/api/v1/auth/sso/apple",
        json={"id_token": token, "email": "apple_victim@example.com"},
    )
    assert resp.status_code == 422
    assert "access_token" not in resp.text


@pytest.mark.asyncio
async def test_oidc_rejects_wrong_audience_and_unconfigured_issuer(client: AsyncClient):
    wrong_aud = _make_id_token(
        {"sub": "o", "email": "o@example.com", "email_verified": True, "iss": OIDC_ISSUER},
        aud="other-client",
    )
    resp = await client.post(
        "/api/v1/auth/sso/oidc", json={"id_token": wrong_aud, "issuer": OIDC_ISSUER}
    )
    assert resp.status_code == 401

    # A caller-chosen issuer (with a token it minted) is never trusted.
    evil = "https://evil.example.com"
    token = _make_id_token(
        {"sub": "o", "email": "o@example.com", "email_verified": True, "iss": evil},
        key=_ATTACKER_KEY,
        aud=OIDC_CLIENT_ID,
    )
    resp = await client.post("/api/v1/auth/sso/oidc", json={"id_token": token, "issuer": evil})
    assert resp.status_code == 422
