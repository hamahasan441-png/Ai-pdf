"""Tests for the suggest-edits endpoint (Part 4.8, review-first AI editing)."""

from app.core.config import settings

URL = "/api/v1/document-ai/suggest-edits"


def _edits_json(edits):
    """Helper: an async chat_completion_json returning a given edits payload."""
    async def fake_json(*args, **kwargs):
        return {"edits": edits}
    return fake_json


async def test_suggest_edits_success(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    monkeypatch.setattr(
        provider_mod.ai_provider,
        "chat_completion_json",
        _edits_json([
            {"original": "teh", "suggestion": "the", "reason": "typo", "category": "spelling"},
            {"original": "very good", "suggestion": "excellent", "reason": "concise", "category": "conciseness"},
        ]),
    )
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(URL, json={"text": "teh report is very good"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 2
    assert body["edits"][0]["original"] == "teh"
    assert body["edits"][0]["suggestion"] == "the"
    assert body["edits"][0]["category"] == "spelling"


async def test_suggest_edits_accepts_bare_array(client, mock_ai, monkeypatch):
    """Model returning a bare JSON array (not wrapped in {edits:...}) still parses."""
    from app.services.ai import provider as provider_mod

    async def fake_json(*args, **kwargs):
        return [{"original": "cat", "suggestion": "dog"}]

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", fake_json)
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(URL, json={"text": "the cat sat"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    assert body["edits"][0]["category"] == "other"  # normalised default


async def test_suggest_edits_filters_invalid(client, mock_ai, monkeypatch):
    """Empty spans, no-op edits, and bad shapes are dropped."""
    from app.services.ai import provider as provider_mod

    monkeypatch.setattr(
        provider_mod.ai_provider,
        "chat_completion_json",
        _edits_json([
            {"original": "", "suggestion": "x"},          # no original -> skip
            {"original": "same", "suggestion": "same"},    # no-op -> skip
            {"original": "y"},                              # no suggestion -> skip
            "not-a-dict",                                   # wrong type -> skip
            {"original": "colour", "suggestion": "color", "category": "SPELLING"},  # kept, normalised
        ]),
    )
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(URL, json={"text": "colour same y"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 1
    assert body["edits"][0]["original"] == "colour"
    assert body["edits"][0]["category"] == "spelling"


async def test_suggest_edits_empty_when_clean(client, mock_ai, monkeypatch):
    from app.services.ai import provider as provider_mod

    monkeypatch.setattr(provider_mod.ai_provider, "chat_completion_json", _edits_json([]))
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(URL, json={"text": "This sentence is already clear."})
    assert resp.status_code == 200
    body = resp.json()
    assert body["count"] == 0
    assert body["edits"] == []


async def test_suggest_edits_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(URL, json={"text": "hello"})
    assert resp.status_code == 503


async def test_suggest_edits_metered(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(URL, json={"text": "a"})
    assert first.status_code == 200
    second = await client.post(URL, json={"text": "b"})
    assert second.status_code == 429
