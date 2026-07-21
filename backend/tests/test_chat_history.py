"""Tests for chat history persistence endpoints (Part 7.3)."""

AUTH = "/api/v1/auth"
CHAT = "/api/v1/chat-history"


async def _register(client, email="user@example.com"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


async def test_create_session(client):
    token = await _register(client)
    resp = await client.post(
        CHAT, headers=_hdr(token), json={"title": "Tax Q&A", "document_id": "doc123"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["title"] == "Tax Q&A"
    assert body["document_id"] == "doc123"
    assert body["message_count"] == 0


async def test_append_and_get_messages(client):
    token = await _register(client)
    session = (await client.post(CHAT, headers=_hdr(token), json={"title": "Chat"})).json()
    sid = session["id"]

    # Append user message
    m1 = await client.post(
        f"{CHAT}/{sid}/messages", headers=_hdr(token),
        json={"role": "user", "content": "What is this about?"},
    )
    assert m1.status_code == 201

    # Append assistant message
    m2 = await client.post(
        f"{CHAT}/{sid}/messages", headers=_hdr(token),
        json={"role": "assistant", "content": "This is about taxes."},
    )
    assert m2.status_code == 201

    # Get session detail
    detail = (await client.get(f"{CHAT}/{sid}", headers=_hdr(token))).json()
    assert len(detail["messages"]) == 2
    assert detail["messages"][0]["role"] == "user"
    assert detail["messages"][1]["role"] == "assistant"


async def test_list_sessions(client):
    token = await _register(client)
    await client.post(CHAT, headers=_hdr(token), json={"title": "A"})
    await client.post(CHAT, headers=_hdr(token), json={"title": "B"})

    resp = await client.get(CHAT, headers=_hdr(token))
    assert resp.status_code == 200
    assert len(resp.json()) == 2


async def test_delete_session(client):
    token = await _register(client)
    session = (await client.post(CHAT, headers=_hdr(token), json={"title": "X"})).json()

    resp = await client.request("DELETE", f"{CHAT}/{session['id']}", headers=_hdr(token))
    assert resp.status_code == 204

    listed = (await client.get(CHAT, headers=_hdr(token))).json()
    assert len(listed) == 0


async def test_cannot_access_others_session(client):
    t1 = await _register(client, "a@x.com")
    t2 = await _register(client, "b@x.com")
    session = (await client.post(CHAT, headers=_hdr(t1), json={"title": "Private"})).json()

    resp = await client.get(f"{CHAT}/{session['id']}", headers=_hdr(t2))
    assert resp.status_code == 404


async def test_invalid_role_rejected(client):
    token = await _register(client)
    session = (await client.post(CHAT, headers=_hdr(token), json={"title": "X"})).json()
    resp = await client.post(
        f"{CHAT}/{session['id']}/messages", headers=_hdr(token),
        json={"role": "hacker", "content": "bad"},
    )
    assert resp.status_code == 422
