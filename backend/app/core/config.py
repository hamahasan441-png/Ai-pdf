"""Application configuration using pydantic-settings."""

from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    # Application
    APP_NAME: str = "AI Document Assistant"
    APP_ENV: str = "development"
    DEBUG: bool = True
    SECRET_KEY: str = "change-me-to-a-random-secret-key"

    # Database
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/ai_pdf_db"

    # Redis
    REDIS_URL: str = "redis://localhost:6379/0"

    # AI Provider - OpenRouter (OpenAI-compatible, 400+ models)
    # Docs: https://openrouter.ai/docs
    AI_API_BASE_URL: str = "https://openrouter.ai/api/v1"
    AI_API_KEY: str = ""  # Set in .env file (never commit keys!)
    AI_MODEL: str = "google/gemini-2.0-flash-exp:free"
    AI_MODEL_ADVANCED: str = "google/gemini-2.5-flash-preview-05-20"
    AI_FALLBACK_MODELS: List[str] = [
        "google/gemini-2.0-flash-exp:free",
        "google/gemini-2.5-flash-preview-05-20",
        "meta-llama/llama-3.1-8b-instruct:free",
        "qwen/qwen-2.5-72b-instruct:free",
        "mistralai/mistral-7b-instruct:free",
    ]

    # JWT
    JWT_SECRET_KEY: str = "change-me-jwt-secret"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    JWT_REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # Encryption
    ENCRYPTION_KEY: str = "change-me-32-byte-encryption-key"

    # File Upload
    MAX_UPLOAD_SIZE_MB: int = 50
    UPLOAD_DIR: str = "./uploads"

    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:8080"]


settings = Settings()
