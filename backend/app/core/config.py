"""Application configuration using pydantic-settings."""

from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict

# Security-critical settings whose shipped defaults are placeholders. They are
# fine for local development but MUST be overridden in production. The startup
# guard (validate_production_secrets) refuses to boot if any remain default
# while APP_ENV is production.
_INSECURE_DEFAULTS: dict[str, str] = {
    "SECRET_KEY": "change-me-to-a-random-secret-key",
    "JWT_SECRET_KEY": "change-me-jwt-secret",
    "ENCRYPTION_KEY": "change-me-32-byte-encryption-key",
}


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

    # Vision models (for image/scan understanding) - must support image input
    AI_VISION_MODELS: List[str] = [
        "google/gemini-2.0-flash-exp:free",
        "meta-llama/llama-3.2-11b-vision-instruct:free",
        "google/gemma-4-26b-a4b-it:free",
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

    # Managed AI metering (free tier). Pro users (verified purchase) are unlimited.
    AI_FREE_DAILY_LIMIT: int = 15
    # Metering backend for the free-tier counter:
    #   "auto"   -> Redis when REDIS_URL is reachable, else in-memory (default)
    #   "memory" -> always in-memory (single instance / dev / tests)
    #   "redis"  -> always Redis (fail closed to in-memory if the client errors)
    # Redis is required for correct metering across multiple backend instances.
    AI_METER_BACKEND: str = "auto"

    # Admin dashboard access. When empty, the /admin/* endpoints return 503
    # (disabled). Set a long random token and send it as the X-Admin-Token
    # header to read aggregate usage/enterprise metrics.
    ADMIN_API_TOKEN: str = ""

    # Google Play Billing verification (server-side, spoof-proof entitlement).
    # Provide the service-account JSON (raw string or file contents) with the
    # androidpublisher scope, and the app's package name. Leave blank to disable
    # verification (endpoint returns 503).
    GOOGLE_PLAY_PACKAGE_NAME: str = "com.aidocassistant.app"
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: str = ""
    # Product IDs (must match the Flutter app / Play Console).
    PRODUCT_MONTHLY: str = "pro_monthly"
    PRODUCT_YEARLY: str = "pro_yearly"
    PRODUCT_LIFETIME: str = "pro_lifetime"

    # -- Runtime helpers ---------------------------------------------------

    def is_production(self) -> bool:
        """True when running under a production-like environment."""
        return self.APP_ENV.strip().lower() in {"production", "prod"}

    def insecure_defaults(self) -> list[str]:
        """Names of security-critical settings still left at their default."""
        return [
            name
            for name, default in _INSECURE_DEFAULTS.items()
            if getattr(self, name) == default
        ]

    def validate_production_secrets(self) -> None:
        """Refuse to run in production with placeholder secrets.

        No-op in development so local setup stays friction-free.
        """
        if self.is_production():
            insecure = self.insecure_defaults()
            if insecure:
                raise RuntimeError(
                    "Refusing to start in production with default secrets: "
                    + ", ".join(insecure)
                    + ". Set secure values via environment variables."
                )


settings = Settings()
