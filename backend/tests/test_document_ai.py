"""Integration tests for the Document AI endpoints and their metering."""

from app.core.config import settings
from app.models.entitlement import Entitlement

SUMMARIZE = "/api/v1/document-ai/summarize"
TRANSLATE = "/api/v1/document-ai/translate"
EXTRACT = "/api/v1/document-ai/extract"
CHAT = "/api/v1/document-ai/chat"
ANALYZE = "/api/v1/document-ai/analyze"
FIX_OCR = "/api/v1/document-ai/fix-ocr"


async def test_summarize_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(SUMMARIZE, json={"document_text": "hello world"})
    assert resp.status_code == 503


async def test_summarize_success(client, mock_ai):
    resp = await client.post(SUMMARIZE, json={"document_text": "hello world", "style": "brief"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["summary"] == "MOCK_REPLY"
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_summarize_large_doc_uses_map_reduce(client, monkeypatch, mock_ai):
    """Documents > _MAP_REDUCE_THRESHOLD chars must go through map-reduce."""
    from app.api.v1 import document_ai as dai_mod
    from app.services.ai import map_reduce_summarizer as mr_mod

    calls: list[str] = []

    async def fake_map_reduce(text, *, chunk_size=3000, style="structured", language="auto"):
        calls.append("map_reduce")
        return "MAP_REDUCE_REPLY"

    monkeypatch.setattr(mr_mod, "map_reduce_summarize", fake_map_reduce)
    # Also make the module-level reference in document_ai point to the patched version.
    monkeypatch.setattr(dai_mod, "map_reduce_summarize", fake_map_reduce)

    big_text = "x" * (dai_mod._MAP_REDUCE_THRESHOLD + 1)
    resp = await client.post(SUMMARIZE, json={"document_text": big_text, "style": "structured"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["summary"] == "MAP_REDUCE_REPLY"
    assert "map_reduce" in calls


async def test_summarize_short_doc_skips_map_reduce(client, monkeypatch, mock_ai):
    """Documents <= _MAP_REDUCE_THRESHOLD chars use the direct AI path."""
    from app.api.v1 import document_ai as dai_mod
    from app.services.ai import map_reduce_summarizer as mr_mod

    calls: list[str] = []

    async def fake_map_reduce(*args, **kwargs):
        calls.append("map_reduce")
        return "SHOULD_NOT_BE_CALLED"

    monkeypatch.setattr(mr_mod, "map_reduce_summarize", fake_map_reduce)
    monkeypatch.setattr(dai_mod, "map_reduce_summarize", fake_map_reduce)

    short_text = "x" * dai_mod._MAP_REDUCE_THRESHOLD  # exactly at threshold → direct path
    resp = await client.post(SUMMARIZE, json={"document_text": short_text})
    assert resp.status_code == 200
    assert resp.json()["summary"] == "MOCK_REPLY"
    assert calls == []  # map-reduce was NOT called


async def test_translate_success(client, mock_ai):
    resp = await client.post(TRANSLATE, json={"text": "hello", "target_language": "Kurdish (Sorani)"})
    assert resp.status_code == 200
    assert resp.json()["translated_text"] == "MOCK_REPLY"


async def test_extract_returns_json(client, mock_ai):
    resp = await client.post(EXTRACT, json={"document_text": "Invoice #42, total 100 USD"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["data"] == {"mock": True, "field": "value"}


async def test_document_chat_success(client, mock_ai):
    resp = await client.post(
        CHAT,
        json={"document_text": "The sky is blue.", "question": "What color is the sky?"},
    )
    assert resp.status_code == 200
    assert resp.json()["answer"] == "MOCK_REPLY"


async def test_analyze_returns_structured_json(client, mock_ai):
    resp = await client.post(ANALYZE, json={"document_text": "Invoice #42, total 100 USD, due 2026-01-01"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["analysis"] == {"mock": True, "field": "value"}
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_analyze_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(ANALYZE, json={"document_text": "hello"})
    assert resp.status_code == 503


async def test_fix_ocr_success(client, mock_ai):
    resp = await client.post(FIX_OCR, json={"text": "He1lo w0rld rn"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["corrected_text"] == "MOCK_REPLY"
    assert body["remaining"] == settings.AI_FREE_DAILY_LIMIT - 1


async def test_fix_ocr_503_when_not_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "")
    resp = await client.post(FIX_OCR, json={"text": "He1lo"})
    assert resp.status_code == 503


async def test_metering_429_across_calls(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    first = await client.post(SUMMARIZE, json={"document_text": "a"})
    assert first.status_code == 200
    # Same identity, limit reached -> next Document AI call is blocked.
    second = await client.post(TRANSLATE, json={"text": "a", "target_language": "German"})
    assert second.status_code == 429


async def test_pro_entitlement_is_unlimited(client, session_maker, mock_ai, monkeypatch):
    # Even with a free limit of 1, a verified Pro token bypasses the cap.
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    async with session_maker() as s:
        s.add(
            Entitlement(
                purchase_token="pro-token-xyz",
                product_id="pro_lifetime",
                tier="lifetime",
                valid=True,
            )
        )
        await s.commit()

    headers = {"X-Entitlement-Token": "pro-token-xyz"}
    first = await client.post(SUMMARIZE, json={"document_text": "a"}, headers=headers)
    second = await client.post(SUMMARIZE, json={"document_text": "b"}, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    # Unlimited sentinel.
    assert first.json()["remaining"] == -1
    assert second.json()["remaining"] == -1


async def test_basic_entitlement_uses_higher_limit(client, session_maker, mock_ai, monkeypatch):
    """A 'basic' tier entitlement should give AI_BASIC_DAILY_LIMIT quota."""
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    monkeypatch.setattr(settings, "AI_BASIC_DAILY_LIMIT", 5)
    async with session_maker() as s:
        s.add(
            Entitlement(
                purchase_token="basic-token-abc",
                product_id="pro_monthly",  # product_id doesn't control tier; tier field does
                tier="basic",
                valid=True,
            )
        )
        await s.commit()

    headers = {"X-Entitlement-Token": "basic-token-abc"}
    # Should succeed up to AI_BASIC_DAILY_LIMIT (5), not hit free limit (1).
    first = await client.post(SUMMARIZE, json={"document_text": "a"}, headers=headers)
    second = await client.post(SUMMARIZE, json={"document_text": "b"}, headers=headers)
    assert first.status_code == 200
    assert second.status_code == 200
    # Still counting — not unlimited.
    assert first.json()["remaining"] != -1
