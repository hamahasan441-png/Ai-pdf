"""OpenRouter AI provider - OpenAI-compatible API client.

OpenRouter: https://openrouter.ai
- 400+ models available (GPT-4o, Claude, Gemini, Llama, Qwen, Mistral)
- OpenAI-compatible API at https://openrouter.ai/api/v1
- Many free models available (Gemini Flash, Llama, Qwen, Mistral)
- Docs: https://openrouter.ai/docs
"""

import json
import logging
import re
from typing import Any, Optional

import httpx

from app.core.config import settings
from app.core.exceptions import AIServiceError

logger = logging.getLogger(__name__)


class AIProvider:
    """Client for OpenRouter API (OpenAI-compatible).

    Features:
    - Automatic model fallback on failure
    - JSON mode for structured outputs
    - Advanced model selection for complex tasks
    - HTTP-Referer header for OpenRouter identification
    """

    def __init__(self):
        self.base_url = settings.AI_API_BASE_URL
        self.api_key = settings.AI_API_KEY
        self.model = settings.AI_MODEL
        self.model_advanced = settings.AI_MODEL_ADVANCED
        self.fallback_models = settings.AI_FALLBACK_MODELS
        self.client = httpx.AsyncClient(
            base_url=self.base_url,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "HTTP-Referer": "https://ai-pdf.app",
                "X-Title": "AI PDF Document Assistant",
            },
            timeout=90.0,
        )

    async def chat_completion(
        self,
        messages: list[dict[str, str]],
        temperature: float = 0.3,
        max_tokens: int = 4096,
        response_format: Optional[dict] = None,
        use_advanced: bool = False,
    ) -> str:
        """Send a chat completion request with automatic model fallback.

        Args:
            messages: Chat messages
            temperature: Response randomness (0=deterministic, 1=creative)
            max_tokens: Max response length
            response_format: Optional {"type": "json_object"} for JSON mode
            use_advanced: Use the advanced model for complex tasks

        Returns:
            Response text content
        """
        model = self.model_advanced if use_advanced else self.model
        models_to_try = [model] + [m for m in self.fallback_models if m != model]

        last_error = None
        for try_model in models_to_try:
            try:
                result = await self._call_api(
                    try_model, messages, temperature, max_tokens, response_format
                )
                return result
            except AIServiceError as e:
                last_error = e
                logger.warning(f"Model {try_model} failed: {e}. Trying next...")
                continue

        raise last_error or AIServiceError("All AI models failed")

    async def _call_api(
        self,
        model: str,
        messages: list[dict[str, str]],
        temperature: float,
        max_tokens: int,
        response_format: Optional[dict],
    ) -> str:
        """Make a single API call to OpenRouter."""
        payload: dict[str, Any] = {
            "model": model,
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
            content = data["choices"][0]["message"]["content"]
            logger.info(f"AI response from {model}: {len(content)} chars")
            return content
        except httpx.HTTPStatusError as e:
            raise AIServiceError(
                f"OpenRouter ({model}) returned status {e.response.status_code}: {e.response.text}"
            )
        except (httpx.RequestError, KeyError, IndexError) as e:
            raise AIServiceError(f"OpenRouter ({model}) request failed: {str(e)}")

    async def chat_completion_json(
        self,
        messages: list[dict[str, str]],
        temperature: float = 0.1,
        max_tokens: int = 4096,
        use_advanced: bool = False,
    ) -> dict:
        """Send a chat completion and parse response as JSON."""
        # Add JSON instruction to system message for models that don't support response_format
        json_messages = list(messages)
        if json_messages and json_messages[0]["role"] == "system":
            json_messages[0] = {
                "role": "system",
                "content": json_messages[0]["content"] + "\n\nIMPORTANT: You MUST respond ONLY with valid JSON. No markdown, no explanation, just JSON.",
            }

        response_text = await self.chat_completion(
            messages=json_messages,
            temperature=temperature,
            max_tokens=max_tokens,
            response_format={"type": "json_object"},
            use_advanced=use_advanced,
        )
        try:
            return json.loads(response_text)
        except json.JSONDecodeError:
            # Try to extract JSON from response (some models wrap in markdown)
            json_match = re.search(r'```(?:json)?\s*([\s\S]*?)```', response_text)
            if json_match:
                try:
                    return json.loads(json_match.group(1))
                except json.JSONDecodeError:
                    pass
            # Try raw JSON extraction
            json_match = re.search(r'\{[\s\S]*\}', response_text)
            if json_match:
                try:
                    return json.loads(json_match.group())
                except json.JSONDecodeError:
                    pass
            raise AIServiceError(f"Failed to parse AI JSON response: {response_text[:300]}")

    async def analyze_document(
        self,
        document_text: str,
        task_prompt: str,
    ) -> dict:
        """Use advanced model for document understanding tasks."""
        messages = [
            {
                "role": "system",
                "content": "You are an expert document analyzer. Always respond in valid JSON format. Never use markdown code blocks.",
            },
            {
                "role": "user",
                "content": f"{task_prompt}\n\nDocument content:\n{document_text[:8000]}",
            },
        ]
        return await self.chat_completion_json(
            messages=messages,
            use_advanced=True,
            max_tokens=4096,
        )

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()


# Singleton instance
ai_provider = AIProvider()
