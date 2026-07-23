"""Integration tests for the extract-dates and extract-actions endpoints."""

from app.core.config import settings

EXTRACT_DATES = "/api/v1/document-ai/extract-dates"
EXTRACT_ACTIONS = "/api/v1/document-ai/extract-actions"


# ── Extract Dates ────────────────────────────────────────────────────────────


async def test_extract_dates_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(EXTRACT_DATES, json={"document_text": "Due by Jan 1 2026"})
    assert resp.status_code == 503


async def test_extract_dates_success(client, mock_ai):
    resp = await client.post(
        EXTRACT_DATES,
        json={"document_text": "Contract expires on 2026-12-31. Payment due 2026-01-15."},
    )
    assert resp.status_code == 200
    body = resp.json()
    # mock_ai returns {"mock": True, "field": "value"} from chat_completion_json,
    # which doesn't have "dates" key → defaults to empty list.
    assert "dates" in body
    assert isinstance(body["dates"], list)
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_extract_dates_429_when_limit_exceeded(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(EXTRACT_DATES, json={"document_text": "Due Jan 1"})
    assert first.status_code == 200
    second = await client.post(EXTRACT_DATES, json={"document_text": "Due Feb 1"})
    assert second.status_code == 429


async def test_extract_dates_validates_empty_text(client, mock_ai):
    """An empty document_text should still be accepted (pydantic max_length only)."""
    resp = await client.post(EXTRACT_DATES, json={"document_text": ""})
    # Empty text is valid per the schema (min_length not set).
    assert resp.status_code == 200


# ── Extract Actions ──────────────────────────────────────────────────────────


async def test_extract_actions_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(EXTRACT_ACTIONS, json={"document_text": "Please sign by Friday"})
    assert resp.status_code == 503


async def test_extract_actions_success(client, mock_ai):
    resp = await client.post(
        EXTRACT_ACTIONS,
        json={"document_text": "Action: submit report by Monday. John to review the budget."},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "actions" in body
    assert isinstance(body["actions"], list)
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_extract_actions_429_when_limit_exceeded(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(EXTRACT_ACTIONS, json={"document_text": "Do this"})
    assert first.status_code == 200
    second = await client.post(EXTRACT_ACTIONS, json={"document_text": "Do that"})
    assert second.status_code == 429


async def test_extract_actions_validates_max_length(client, mock_ai):
    """Document text exceeding max_length should be rejected by pydantic."""
    long_text = "x" * 30001
    resp = await client.post(EXTRACT_ACTIONS, json={"document_text": long_text})
    assert resp.status_code == 422  # Validation error
