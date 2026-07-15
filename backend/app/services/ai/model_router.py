"""Smart Model Router - Selects the optimal AI model per task.

Engineering Decision:
  Instead of always using the same model, we select the best model
  based on the task type, balancing quality, speed, and cost.

  - Simple tasks (field mapping, validation) → fastest free model
  - Complex tasks (document analysis) → best free model
  - Vision tasks (images, scans) → vision-capable free model

  This minimizes API cost while maximizing quality.

  Future: Add latency-based routing, cost tracking, and A/B testing.
"""

import logging
from enum import Enum
from typing import Optional

from app.core.config import settings

logger = logging.getLogger(__name__)


class TaskType(str, Enum):
    """Types of AI tasks with different model requirements."""
    QUICK = "quick"           # Field mapping, formatting, simple Q&A
    ANALYSIS = "analysis"     # Document understanding, complex reasoning
    VISION = "vision"         # Image understanding, OCR
    GENERATION = "generation" # Text generation, summaries
    VALIDATION = "validation" # Form validation, error checking


# Model selection strategy per task type
# Ordered by preference (first = best choice)
MODEL_STRATEGY = {
    TaskType.QUICK: [
        "google/gemini-2.0-flash-exp:free",       # Fast, free, good quality
        "meta-llama/llama-3.1-8b-instruct:free",  # Fast fallback
        "mistralai/mistral-7b-instruct:free",     # Lightweight fallback
    ],
    TaskType.ANALYSIS: [
        "google/gemini-2.0-flash-exp:free",       # Best free model for analysis
        "google/gemini-2.5-flash-preview-05-20",  # Advanced (may cost)
        "qwen/qwen-2.5-72b-instruct:free",       # Strong reasoning
    ],
    TaskType.VISION: [
        "google/gemini-2.0-flash-exp:free",       # Best free vision
        "meta-llama/llama-3.2-11b-vision-instruct:free",  # Vision fallback
        "google/gemma-4-26b-a4b-it:free",         # Multimodal MoE
    ],
    TaskType.GENERATION: [
        "google/gemini-2.0-flash-exp:free",       # Good generation
        "qwen/qwen-2.5-72b-instruct:free",       # Strong writing
        "mistralai/mistral-7b-instruct:free",     # Fast generation
    ],
    TaskType.VALIDATION: [
        "meta-llama/llama-3.1-8b-instruct:free",  # Fast, sufficient for checks
        "google/gemini-2.0-flash-exp:free",       # Better accuracy
        "mistralai/mistral-7b-instruct:free",     # Fallback
    ],
}


class ModelRouter:
    """Routes AI requests to the optimal model based on task type.

    Design principles:
    - Free models first (minimize cost)
    - Match model capability to task complexity
    - Automatic fallback on failure
    - Track which models succeed/fail for future optimization
    """

    def get_models_for_task(self, task: TaskType) -> list[str]:
        """Get ordered list of models to try for a given task."""
        models = MODEL_STRATEGY.get(task, MODEL_STRATEGY[TaskType.QUICK])
        logger.debug(f"Model route for {task.value}: {models[0]}")
        return models

    def get_primary_model(self, task: TaskType) -> str:
        """Get the primary (first choice) model for a task."""
        return self.get_models_for_task(task)[0]

    def get_vision_models(self) -> list[str]:
        """Get all vision-capable models."""
        return MODEL_STRATEGY[TaskType.VISION]

    def is_free_model(self, model: str) -> bool:
        """Check if a model is free (no cost)."""
        return ":free" in model


# Singleton
model_router = ModelRouter()
