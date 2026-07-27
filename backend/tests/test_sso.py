"""Tests for SSO OIDC — E5.3 Enhancement-Based Masterplan."""

import base64
import json

import jwt as pyjwt
import pytest
from httpx import AsyncClient

from app.core.config import settings


def _make_id_token(payload: dict) -> str:
    # Create unsigned JWT (alg=none) for test — payload must contain email, sub, etc.
    # PyJWT requires key for none? Use encode with key="" and alg=none is allowed if options.
    # We'll create header+payload+empty signature manually using base64url.
    header = {"alg": "none", "typ": "JWT"}
    def b64url(obj):
        return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")
    token = f"{b64url(header)}.{b64url(payload)}."
    return token


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
    payload = {"sub": "apple-123", "email": "sso_apple@example.com"}
    id_token = _make_id_token(payload)
    resp = await client.post(
        "/api/v1/auth/sso/apple",
        json={"id_token": id_token, "email": "sso_apple@example.com", "full_name": "Apple User"},
    )
    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_generic_oidc_sso(client: AsyncClient):
    issuer = "https://example.okta.com"
    payload = {"email": "oidc@example.com", "sub": "oidc-123", "iss": issuer, "name": "OIDC User"}
    id_token = _make_id_token(payload)
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
