"""Tests for webhook subscription endpoints (Part 7.2)."""

AUTH = "/api/v1/auth"
HOOKS = "/api/v1/webhooks"


async def _register(client, email="user@example.com"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


async def test_list_event_types(client):
    resp = await client.get(f"{HOOKS}/event-types")
    assert resp.status_code == 200
    assert "ai.chat.complete" in resp.json()["event_types"]


async def test_create_webhook(client):
    token = await _register(client)
    resp = await client.post(
        HOOKS,
        headers=_hdr(token),
        json={"url": "https://example.com/hook", "events": ["ai.chat.complete"]},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["url"] == "https://example.com/hook"
    assert body["events"] == ["ai.chat.complete"]
    assert len(body["secret"]) > 20
    assert body["active"] is True


async def test_create_webhook_invalid_event(client):
    token = await _register(client)
    resp = await client.post(
        HOOKS,
        headers=_hdr(token),
        json={"url": "https://example.com/hook", "events": ["not.a.real.event"]},
    )
    assert resp.status_code == 422


async def test_list_webhooks(client):
    token = await _register(client)
    await client.post(
        HOOKS, headers=_hdr(token),
        json={"url": "https://a.com/h", "events": ["ai.chat.complete"]},
    )
    await client.post(
        HOOKS, headers=_hdr(token),
        json={"url": "https://b.com/h", "events": ["document.indexed"]},
    )
    resp = await client.get(HOOKS, headers=_hdr(token))
    assert resp.status_code == 200
    assert len(resp.json()) == 2


async def test_delete_webhook(client):
    token = await _register(client)
    created = (
        await client.post(
            HOOKS, headers=_hdr(token),
            json={"url": "https://del.com/h", "events": ["ai.chat.complete"]},
        )
    ).json()

    resp = await client.request("DELETE", f"{HOOKS}/{created['id']}", headers=_hdr(token))
    assert resp.status_code == 204

    listed = (await client.get(HOOKS, headers=_hdr(token))).json()
    assert len(listed) == 0


async def test_cannot_delete_others_webhook(client):
    t1 = await _register(client, "a@x.com")
    t2 = await _register(client, "b@x.com")
    created = (
        await client.post(
            HOOKS, headers=_hdr(t1),
            json={"url": "https://x.com/h", "events": ["ai.chat.complete"]},
        )
    ).json()

    resp = await client.request("DELETE", f"{HOOKS}/{created['id']}", headers=_hdr(t2))
    assert resp.status_code == 404
