from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CODEATLAS_", env_file=".env", extra="ignore")

    environment: str = Field(default="development", alias="CODEATLAS_ENV")
    api_base_url: str = "http://localhost:8000"
    database_url: str = "postgresql+asyncpg://codeatlas:codeatlas@localhost:5432/codeatlas"
    redis_url: str = "redis://localhost:6379/0"
    jwt_issuer: str = "codeatlas"
    jwt_audience: str = "codeatlas-ios"
    jwt_secret: str = "development-only-change-me-codeatlas-local"
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    apple_audience: str | None = None
    github_client_id: str | None = None
    github_client_secret: str | None = None
    github_oauth_redirect_url: str = "http://127.0.0.1:8000/api/v1/repositories/github/oauth/callback"
    llm_provider: str = "disabled"
    llm_api_key: str | None = None
    storage_backend: str = "local"
    allowed_origins: list[str] = ["http://localhost:3000", "http://127.0.0.1:3000"]
    rate_limit_requests_per_minute: int = 120
    max_request_bytes: int = 2_000_000
    local_data_path: str = ".codeatlas_data/repositories.json"

    @field_validator("jwt_secret")
    @classmethod
    def validate_jwt_secret(cls, value: str) -> str:
        if len(value) < 32:
            raise ValueError("CODEATLAS_JWT_SECRET must be at least 32 characters.")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
