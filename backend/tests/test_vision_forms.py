"""Tests for vision forms detection — E2.7 Phase 5."""

import base64

import pytest
from httpx import AsyncClient

from app.core.config import settings


def _dummy_jpeg_base64() -> str:
    # 1x1 white JPEG base64 (minimal valid image)
    # This is a 1x1 pixel JPEG
    return "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAv/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAAAAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCwAA8A/9k="


@pytest.mark.asyncio
async def test_vision_detect_endpoint(client: AsyncClient, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(
        "/api/v1/forms/vision-detect",
        json={
            "fields": [
                {
                    "label": "First Name",
                    "detected_type": "text",
                    "confidence": 0.3,
                    "language": "en",
                    "image_base64": _dummy_jpeg_base64(),
                    "image_mime": "image/jpeg",
                }
            ],
            "language": "en",
        },
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert "fields" in data
    assert len(data["fields"]) >= 1
    assert "model_used" in data


@pytest.mark.asyncio
async def test_vision_detect_without_image(client: AsyncClient, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_API_KEY", "test-key")

    resp = await client.post(
        "/api/v1/forms/vision-detect",
        json={
            "fields": [
                {
                    "label": "Email address",
                    "detected_type": "text",
                    "confidence": 0.2,
                }
            ]
        },
    )
    assert resp.status_code == 200
    assert len(resp.json()["fields"]) == 1
