"""Tests for the multi-document chat endpoints."""

from app.core.config import settings

INDEX = "/api/v1/document-ai/multi-doc/index"
CHAT = "/api/v1/document-ai/multi-doc/chat"
CLEAR = "/api/v1/document-ai/multi-doc/session/test-session"


async def test_index_and_chat(client, mock_ai):
    # Index a document
    resp = await client.post(INDEX, json={
        "session_id": "test-session",
        "doc_id": "d1",
        "doc_name": "invoice.pdf",
        "pages": {"1": "Total amount 500 EUR payment due 30 days", "2": "Bank IBAN DE89 3704 0044"},
    })
    assert resp.status_code == 200
    body = resp.json()
    assert body["chunks_added"] >= 2
    assert body["docs_indexed"] == 1

    # Chat
    chat_resp = await client.post(CHAT, json={
        "session_id": "test-session",
        "question": "What is the total amount?",
    })
    assert chat_resp.status_code == 200
    chat_body = chat_resp.json()
    assert chat_body["answer"] == "MOCK_REPLY"
    assert len(chat_body["citations"]) > 0
    assert chat_body["citations"][0]["doc_name"] == "invoice.pdf"


async def test_chat_404_without_index(client, mock_ai):
    resp = await client.post(CHAT, json={
        "session_id": "nonexistent",
        "question": "hello",
    })
    assert resp.status_code == 404


async def test_clear_session(client, mock_ai):
    # Index first
    await client.post(INDEX, json={
        "session_id": "test-session",
        "doc_id": "d1",
        "doc_name": "a.pdf",
        "pages": {"1": "content"},
    })
    # Clear
    resp = await client.delete(CLEAR)
    assert resp.status_code == 200
    # Chat should now 404
    chat_resp = await client.post(CHAT, json={
        "session_id": "test-session",
        "question": "hello",
    })
    assert chat_resp.status_code == 404


async def test_chat_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    # Need to index first
    await client.post(INDEX, json={
        "session_id": "s503",
        "doc_id": "d1",
        "doc_name": "a.pdf",
        "pages": {"1": "content"},
    })
    resp = await client.post(CHAT, json={
        "session_id": "s503",
        "question": "hello",
    })
    assert resp.status_code == 503


# --- Session isolation and size limits (security regressions) --------------


async def _token(client, email):
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "password123", "full_name": "MD User"},
    )
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def test_sessions_are_isolated_between_callers(client, mock_ai):
    alice = await _token(client, "md_alice@example.com")
    bob = await _token(client, "md_bob@example.com")
    body = {"session_id": "shared-name", "doc_id": "d1", "doc_name": "a.pdf", "pages": {"1": "secret salary 9000"}}
    assert (await client.post(INDEX, json=body, headers=alice)).status_code == 200

    # Bob cannot query Alice's session ...
    resp = await client.post(CHAT, json={"session_id": "shared-name", "question": "salary"}, headers=bob)
    assert resp.status_code == 404
    # ... nor delete it.
    await client.delete("/api/v1/document-ai/multi-doc/session/shared-name", headers=bob)
    resp = await client.post(CHAT, json={"session_id": "shared-name", "question": "salary"}, headers=alice)
    assert resp.status_code == 200


async def test_index_size_limits(client, mock_ai, monkeypatch):
    from app.api.v1 import multi_doc_chat as endpoint

    too_many_pages = {str(i): "x" for i in range(endpoint._MAX_PAGES_PER_DOC + 1)}
    resp = await client.post(INDEX, json={"session_id": "big", "doc_id": "d", "doc_name": "n", "pages": too_many_pages})
    assert resp.status_code == 422

    long_page = {"1": "x" * (endpoint._MAX_PAGE_CHARS + 1)}
    resp = await client.post(INDEX, json={"session_id": "big", "doc_id": "d", "doc_name": "n", "pages": long_page})
    assert resp.status_code == 422

    monkeypatch.setattr(endpoint, "_MAX_DOCS_PER_SESSION", 2)
    for i in range(2):
        ok = await client.post(INDEX, json={"session_id": "big", "doc_id": f"d{i}", "doc_name": "n", "pages": {"1": "invoice total amount"}})
        assert ok.status_code == 200
    resp = await client.post(INDEX, json={"session_id": "big", "doc_id": "d9", "doc_name": "n", "pages": {"1": "invoice total amount"}})
    assert resp.status_code == 422
