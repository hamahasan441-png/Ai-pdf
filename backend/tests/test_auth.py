"""Integration tests for the auth endpoints (register/login/refresh/me/change)."""

BASE = "/api/v1/auth"


async def _register(client, email="user@example.com", password="password123", name="Test User"):
    return await client.post(
        f"{BASE}/register",
        json={"email": email, "password": password, "full_name": name},
    )


async def test_register_returns_tokens(client):
    resp = await _register(client)
    assert resp.status_code == 201
    body = resp.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["token_type"] == "bearer"
    assert body["expires_in"] > 0


async def test_register_duplicate_email_rejected(client):
    await _register(client)
    resp = await _register(client)
    assert resp.status_code == 422


async def test_login_success(client):
    await _register(client)
    resp = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "password123"})
    assert resp.status_code == 200
    assert resp.json()["access_token"]


async def test_login_wrong_password(client):
    await _register(client)
    resp = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "WRONG"})
    assert resp.status_code == 401


async def test_login_unknown_email(client):
    resp = await client.post(f"{BASE}/login", json={"email": "nobody@example.com", "password": "whatever"})
    assert resp.status_code == 401


async def test_me_requires_valid_token(client):
    await _register(client)
    login = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "password123"})
    token = login.json()["access_token"]

    ok = await client.get(f"{BASE}/me", headers={"Authorization": f"Bearer {token}"})
    assert ok.status_code == 200
    assert ok.json()["email"] == "user@example.com"

    bad = await client.get(f"{BASE}/me", headers={"Authorization": "Bearer not-a-real-token"})
    assert bad.status_code == 401


async def test_refresh_rotates_tokens(client):
    reg = await _register(client)
    refresh = reg.json()["refresh_token"]

    resp = await client.post(f"{BASE}/refresh", json={"refresh_token": refresh})
    assert resp.status_code == 200
    assert resp.json()["access_token"]


async def test_refresh_rejects_access_token(client):
    reg = await _register(client)
    access = reg.json()["access_token"]

    # Passing an access token where a refresh token is expected must fail.
    resp = await client.post(f"{BASE}/refresh", json={"refresh_token": access})
    assert resp.status_code == 401


async def test_change_password_flow(client):
    await _register(client)
    login = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "password123"})
    token = login.json()["access_token"]

    changed = await client.post(
        f"{BASE}/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={"current_password": "password123", "new_password": "newpassword456"},
    )
    assert changed.status_code == 204

    # Old password no longer works.
    old = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "password123"})
    assert old.status_code == 401

    # New password works.
    new = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "newpassword456"})
    assert new.status_code == 200


async def test_change_password_wrong_current(client):
    await _register(client)
    login = await client.post(f"{BASE}/login", json={"email": "user@example.com", "password": "password123"})
    token = login.json()["access_token"]

    resp = await client.post(
        f"{BASE}/change-password",
        headers={"Authorization": f"Bearer {token}"},
        json={"current_password": "WRONG", "new_password": "newpassword456"},
    )
    assert resp.status_code == 401
