"""FreeTheAI provider - OpenAI-compatible API client."""

import json
from typing import Any, Optional

import httpx

from app.core.config import settings
from app.core.exceptions import AIServiceError


class AIProvider:
    """Client for the FreeTheAI API (OpenAI-compatible)."""

    def __init__(self):
        self.base_url = settings.AI_API_BASE_URL
        self.api_key = settings.AI_API_KEY
        self.model = settings.AI_MODEL
        self.client = httpx.AsyncClient(
            base_url=self.base_url,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            timeout=60.0,
        )

    async def chat_completion(
        self,
        messages: list[dict[str, str]],
        temperature: float = 0.3,
        max_tokens: int = 4096,
        response_format: Optional[dict] = None,
    ) -> str:
        """Send a chat completion request and return the response text."""
        payload: dict[str, Any] = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
        }
        if response_format:
            payload["response_format"] = response_format

        try:
            response = await self.client.post("/chat/completions", json=payload)
            response.raise_for_status()
            data = response.json()
            return data["choices"][0]["message"]["content"]
        except httpx.HTTPStatusError as e:
            raise AIServiceError(
                f"AI API returned status {e.response.status_code}: {e.response.text}"
            )
        except (httpx.RequestError, KeyError, IndexError) as e:
            raise AIServiceError(f"AI API request failed: {str(e)}")

    async def chat_completion_json(
        self,
        messages: list[dict[str, str]],
        temperature: float = 0.1,
        max_tokens: int = 4096,
    ) -> dict:
        """Send a chat completion and parse response as JSON."""
        response_text = await self.chat_completion(
            messages=messages,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format={"type": "json_object"},
        )
        try:
            return json.loads(response_text)
        except json.JSONDecodeError as e:
            raise AIServiceError(f"Failed to parse AI JSON response: {str(e)}")

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()


# Singleton instance
ai_provider = AIProvider()
