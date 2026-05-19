from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    api_prefix: str = "/v1"
    api_title: str = "BinGo Backend V1"
    database_url: str = "sqlite+pysqlite:///:memory:"
    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    token_ttl_minutes: int = 30

    model_config = SettingsConfigDict(
        env_prefix="BINGO_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

