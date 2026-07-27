"""Tests for streaming map-reduce summarization — E2.2."""

import pytest
from httpx import AsyncClient

from app.core.config import settings


@pytest.mark.asyncio
async def test_summarize_stream_endpoint(client: AsyncClient, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")
    # Long text to trigger map-reduce (but mocked AI returns MOCK_REPLY quickly)
    long_text = "Lorem ipsum " * 2000  # ~ 24k chars > threshold

    resp = await client.post(
        "/api/v1/document-ai/summarize/stream",
        json={"document_text": long_text, "style": "brief"},
    )
    assert resp.status_code == 200
    assert "text/event-stream" in resp.headers.get("content-type", "")

    # Read streamed content
    content = resp.content.decode()
    assert "data:" in content
    # Should contain at least one chunk and final or DONE
    assert "MOCK_REPLY" in content or "chunk" in content.lower() or "final" in content.lower()


@pytest.mark.asyncio
async def test_summarize_stream_json_variant(client: AsyncClient, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")
    resp = await client.post(
        "/api/v1/document-ai/summarize/stream/json",
        json={"document_text": "Short text " * 100, "style": "brief"},
    )
    assert resp.status_code == 200
    assert "ndjson" in resp.headers.get("content-type", "") or "json" in resp.headers.get("content-type", "")
    content = resp.content.decode()
    assert "\n" in content
