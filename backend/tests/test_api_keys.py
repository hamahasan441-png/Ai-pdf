"""Tests for API key CRUD endpoints (Part 7.1)."""

AUTH = "/api/v1/auth"
KEYS = "/api/v1/api-keys"


async def _register(client, email="user@example.com"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


async def test_create_api_key(client):
    token = await _register(client)
    resp = await client.post(KEYS, headers=_hdr(token), json={"name": "CI key"})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["name"] == "CI key"
    assert body["key"].startswith("aipdf_")
    assert len(body["key"]) > 20
    assert body["key_prefix"] == body["key"][:12]


async def test_list_api_keys(client):
    token = await _register(client)
    await client.post(KEYS, headers=_hdr(token), json={"name": "Key A"})
    await client.post(KEYS, headers=_hdr(token), json={"name": "Key B"})

    resp = await client.get(KEYS, headers=_hdr(token))
    assert resp.status_code == 200
    keys = resp.json()
    assert len(keys) == 2
    assert all(k["is_active"] for k in keys)


async def test_revoke_api_key(client):
    token = await _register(client)
    created = (await client.post(KEYS, headers=_hdr(token), json={"name": "tmp"})).json()

    resp = await client.request("DELETE", f"{KEYS}/{created['id']}", headers=_hdr(token))
    assert resp.status_code == 204

    listed = (await client.get(KEYS, headers=_hdr(token))).json()
    revoked = [k for k in listed if k["id"] == created["id"]]
    assert revoked[0]["is_active"] is False


async def test_revoke_idempotent(client):
    token = await _register(client)
    created = (await client.post(KEYS, headers=_hdr(token), json={"name": "tmp"})).json()
    await client.request("DELETE", f"{KEYS}/{created['id']}", headers=_hdr(token))
    # Second revoke is idempotent
    resp = await client.request("DELETE", f"{KEYS}/{created['id']}", headers=_hdr(token))
    assert resp.status_code == 204


async def test_cannot_revoke_others_key(client):
    t1 = await _register(client, "a@x.com")
    t2 = await _register(client, "b@x.com")
    created = (await client.post(KEYS, headers=_hdr(t1), json={"name": "mine"})).json()

    resp = await client.request("DELETE", f"{KEYS}/{created['id']}", headers=_hdr(t2))
    assert resp.status_code == 404
