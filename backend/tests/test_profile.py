"""Integration tests for the profile endpoints (auth + encryption round-trip)."""

# Note the trailing slash: the profile routes are mounted at "/" under the
# "/profile" prefix, so the full path is "/api/v1/profile/". Hitting it without
# the slash would trigger a 307 redirect that httpx does not follow by default.
BASE = "/api/v1/profile/"
REGISTER = "/api/v1/auth/register"


async def _auth_header(client, email="profile-user@example.com"):
    resp = await client.post(
        REGISTER,
        json={"email": email, "password": "password123", "full_name": "Profile User"},
    )
    token = resp.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


async def test_get_profile_creates_empty(client):
    headers = await _auth_header(client)
    resp = await client.get(BASE, headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["first_name"] is None
    assert body["ssn_last_four"] is None
    assert body["custom_fields"] is None


async def test_update_encrypts_and_persists(client):
    headers = await _auth_header(client)

    update = {
        "first_name": "Ada",
        "last_name": "Lovelace",
        "ssn": "123456789",
        "custom_fields": {"note": "vip"},
    }
    put = await client.put(BASE, headers=headers, json=update)
    assert put.status_code == 200
    body = put.json()
    assert body["first_name"] == "Ada"
    assert body["last_name"] == "Lovelace"
    # Only the last four digits of the SSN are ever returned.
    assert body["ssn_last_four"] == "6789"
    assert "ssn" not in body
    assert body["custom_fields"] == {"note": "vip"}

    # A fresh request must return the same values (encrypt -> DB -> decrypt).
    get = await client.get(BASE, headers=headers)
    assert get.status_code == 200
    got = get.json()
    assert got["first_name"] == "Ada"
    assert got["custom_fields"] == {"note": "vip"}
    assert got["ssn_last_four"] == "6789"


async def test_partial_update_preserves_other_fields(client):
    headers = await _auth_header(client)
    await client.put(BASE, headers=headers, json={"first_name": "Grace", "city": "NYC"})
    # Update only one field; the other must remain.
    await client.put(BASE, headers=headers, json={"city": "Boston"})

    got = (await client.get(BASE, headers=headers)).json()
    assert got["first_name"] == "Grace"
    assert got["city"] == "Boston"


async def test_profile_requires_valid_token(client):
    resp = await client.get(BASE, headers={"Authorization": "Bearer not-valid"})
    assert resp.status_code == 401
