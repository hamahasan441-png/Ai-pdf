"""Tests for API key scopes — E7.1 Enhancement-Based Masterplan."""

AUTH = "/api/v1/auth"
KEYS = "/api/v1/api-keys"


async def _register(client, email="scope_user@example.com"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


async def test_scopes_endpoint(client):
    resp = await client.get(f"{KEYS}/scopes")
    assert resp.status_code == 200
    data = resp.json()
    assert "allowed_scopes" in data
    assert "ai:read" in data["allowed_scopes"]
    assert "ai:write" in data["default_scopes"]


async def test_create_with_scopes(client):
    token = await _register(client, "scope_a@example.com")
    resp = await client.post(
        KEYS,
        headers=_hdr(token),
        json={"name": "Scoped", "scopes": ["ai:read", "forms:read"]},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert set(body["scopes"]) == {"ai:read", "forms:read"}

    # List returns scopes
    listed = await client.get(KEYS, headers=_hdr(token))
    assert listed.status_code == 200
    assert len(listed.json()) == 1
    assert set(listed.json()[0]["scopes"]) == {"ai:read", "forms:read"}


async def test_create_invalid_scope_rejected(client):
    token = await _register(client, "scope_b@example.com")
    resp = await client.post(
        KEYS, headers=_hdr(token), json={"name": "Bad", "scopes": ["invalid:scope"]}
    )
    assert resp.status_code == 422


async def test_create_default_scopes(client):
    token = await _register(client, "scope_c@example.com")
    resp = await client.post(KEYS, headers=_hdr(token), json={"name": "Default"})
    assert resp.status_code == 201
    scopes = resp.json()["scopes"]
    assert "ai:read" in scopes
    assert len(scopes) >= 3
