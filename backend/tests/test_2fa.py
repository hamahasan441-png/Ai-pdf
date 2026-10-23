"""Tests for TOTP 2FA — E5.2 Enhancement-Based Masterplan."""

import pytest
from httpx import AsyncClient

from app.services.auth.totp import generate_secret, generate_totp, verify_totp, generate_recovery_codes


def test_totp_generate_and_verify():
    secret = generate_secret()
    token = generate_totp(secret)
    assert verify_totp(secret, token)
    assert not verify_totp(secret, "000000")


def test_recovery_codes_format():
    codes = generate_recovery_codes()
    assert len(codes) == 8
    for c in codes:
        assert "-" in c
        assert len(c) == 11  # 5-5 with hyphen


@pytest.mark.asyncio
async def test_2fa_setup_and_verify_flow(client: AsyncClient):
    # Register
    email = "2fa_flow@example.com"
    password = "password123"
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "full_name": "2FA User"},
    )
    assert resp.status_code == 201
    tokens = resp.json()
    access = tokens["access_token"]

    # Setup 2FA
    setup = await client.post(
        "/api/v1/auth/2fa/setup", headers={"Authorization": f"Bearer {access}"}
    )
    assert setup.status_code == 200
    data = setup.json()
    secret = data["secret"]
    assert secret
    assert data["otpauth_url"].startswith("otpauth://")

    # Status should be disabled before verify
    status_resp = await client.get(
        "/api/v1/auth/2fa/status", headers={"Authorization": f"Bearer {access}"}
    )
    assert status_resp.status_code == 200
    assert status_resp.json()["enabled"] is False

    # Verify with correct TOTP
    token = generate_totp(secret)
    verify_resp = await client.post(
        "/api/v1/auth/2fa/verify",
        headers={"Authorization": f"Bearer {access}"},
        json={"totp_code": token},
    )
    assert verify_resp.status_code == 200, verify_resp.text
    v_data = verify_resp.json()
    assert v_data["enabled"] is True
    assert len(v_data["recovery_codes"]) == 8

    # Status now enabled
    status2 = await client.get(
        "/api/v1/auth/2fa/status", headers={"Authorization": f"Bearer {access}"}
    )
    assert status2.json()["enabled"] is True
    assert status2.json()["remaining_recovery_codes"] == 8

    # Login without 2FA code should fail with 401 2FA required
    login_no_2fa = await client.post(
        "/api/v1/auth/login", json={"email": email, "password": password}
    )
    assert login_no_2fa.status_code == 401
    assert "2FA required" in login_no_2fa.text

    # Login with correct TOTP via /login/2fa
    token2 = generate_totp(secret)
    login_2fa = await client.post(
        "/api/v1/auth/login/2fa",
        json={"email": email, "password": password, "totp_code": token2},
    )
    assert login_2fa.status_code == 200, login_2fa.text

    # Regenerate recovery codes
    regen = await client.post(
        "/api/v1/auth/2fa/recovery-codes",
        headers={"Authorization": f"Bearer {access}"},
    )
    assert regen.status_code == 200
    assert len(regen.json()["recovery_codes"]) == 8

    # Use recovery code to login
    recovery_code = regen.json()["recovery_codes"][0]
    login_rec = await client.post(
        "/api/v1/auth/login/2fa",
        json={"email": email, "password": password, "recovery_code": recovery_code},
    )
    assert login_rec.status_code == 200

    # Status after using one recovery code -> 7 remaining (need fresh token, login with TOTP again to get access)
    token3 = generate_totp(secret)
    login_again = await client.post(
        "/api/v1/auth/login/2fa",
        json={"email": email, "password": password, "totp_code": token3},
    )
    assert login_again.status_code == 200
    new_access = login_again.json()["access_token"]
    status3 = await client.get(
        "/api/v1/auth/2fa/status", headers={"Authorization": f"Bearer {new_access}"}
    )
    assert status3.json()["remaining_recovery_codes"] == 7

    # Disable 2FA (requires password + a current code)
    dis = await client.post(
        "/api/v1/auth/2fa/disable",
        headers={"Authorization": f"Bearer {new_access}"},
        json={"password": password, "totp_code": generate_totp(secret)},
    )
    assert dis.status_code == 204

    status4 = await client.get(
        "/api/v1/auth/2fa/status", headers={"Authorization": f"Bearer {new_access}"}
    )
    assert status4.json()["enabled"] is False


@pytest.mark.asyncio
async def test_2fa_wrong_code_rejected(client: AsyncClient):
    email = "2fa_wrong@example.com"
    password = "password123"
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "full_name": "2FA Wrong"},
    )
    access = resp.json()["access_token"]
    setup = await client.post(
        "/api/v1/auth/2fa/setup", headers={"Authorization": f"Bearer {access}"}
    )
    assert setup.status_code == 200

    bad = await client.post(
        "/api/v1/auth/2fa/verify",
        headers={"Authorization": f"Bearer {access}"},
        json={"totp_code": "000000"},
    )
    assert bad.status_code == 401


@pytest.mark.asyncio
async def test_login_2fa_without_setup_works(client: AsyncClient):
    # User without 2FA can still use /login/2fa endpoint (should issue tokens)
    email = "no2fa@example.com"
    password = "password123"
    await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "full_name": "No 2FA"},
    )
    resp = await client.post(
        "/api/v1/auth/login/2fa",
        json={"email": email, "password": password},
    )
    assert resp.status_code == 200


# --- Security regressions: setup must not leak a live secret; disable needs re-auth


async def _enabled_2fa_user(client: AsyncClient, email: str, password: str = "password123"):
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "full_name": "2FA Sec"},
    )
    access = resp.json()["access_token"]
    hdr = {"Authorization": f"Bearer {access}"}
    secret = (await client.post("/api/v1/auth/2fa/setup", headers=hdr)).json()["secret"]
    verify = await client.post("/api/v1/auth/2fa/verify", headers=hdr, json={"totp_code": generate_totp(secret)})
    assert verify.status_code == 200
    return hdr, secret, verify.json()["recovery_codes"]


@pytest.mark.asyncio
async def test_2fa_setup_refuses_when_already_enabled(client: AsyncClient):
    hdr, secret, _ = await _enabled_2fa_user(client, "2fa_sec1@example.com")
    again = await client.post("/api/v1/auth/2fa/setup", headers=hdr)
    assert again.status_code == 409
    assert secret not in again.text
    # Still enabled with the original secret.
    status_resp = await client.get("/api/v1/auth/2fa/status", headers=hdr)
    assert status_resp.json()["enabled"] is True
    login = await client.post(
        "/api/v1/auth/login/2fa",
        json={"email": "2fa_sec1@example.com", "password": "password123", "totp_code": generate_totp(secret)},
    )
    assert login.status_code == 200


@pytest.mark.asyncio
async def test_2fa_disable_requires_password_and_code(client: AsyncClient):
    hdr, secret, _ = await _enabled_2fa_user(client, "2fa_sec2@example.com")

    no_body = await client.post("/api/v1/auth/2fa/disable", headers=hdr)
    assert no_body.status_code == 422

    password_only = await client.post("/api/v1/auth/2fa/disable", headers=hdr, json={"password": "password123"})
    assert password_only.status_code == 401

    wrong_pw = await client.post(
        "/api/v1/auth/2fa/disable",
        headers=hdr,
        json={"password": "wrong-password", "totp_code": generate_totp(secret)},
    )
    assert wrong_pw.status_code == 401

    wrong_code = await client.post(
        "/api/v1/auth/2fa/disable", headers=hdr, json={"password": "password123", "totp_code": "000000"}
    )
    assert wrong_code.status_code == 401

    status_resp = await client.get("/api/v1/auth/2fa/status", headers=hdr)
    assert status_resp.json()["enabled"] is True


@pytest.mark.asyncio
async def test_2fa_disable_with_recovery_code(client: AsyncClient):
    hdr, _, codes = await _enabled_2fa_user(client, "2fa_sec3@example.com")
    dis = await client.post(
        "/api/v1/auth/2fa/disable", headers=hdr, json={"password": "password123", "recovery_code": codes[0]}
    )
    assert dis.status_code == 204
    status_resp = await client.get("/api/v1/auth/2fa/status", headers=hdr)
    assert status_resp.json()["enabled"] is False
