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
