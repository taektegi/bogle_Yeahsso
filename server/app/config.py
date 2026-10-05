from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """환경변수(또는 server/.env)에서 읽는 서버 설정. 새 값을 추가하면 .env.example에도 적는다."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "development"
    log_level: str = "INFO"

    supabase_url: str = ""
    supabase_jwt_secret: SecretStr | None = None

    @property
    def issuer(self) -> str | None:
        """Supabase 토큰의 iss 값. SUPABASE_URL이 없으면 검사하지 않는다."""
        if not self.supabase_url:
            return None
        return f"{self.supabase_url.rstrip('/')}/auth/v1"

    @property
    def jwks_url(self) -> str | None:
        if not self.issuer:
            return None
        return f"{self.issuer}/.well-known/jwks.json"


@lru_cache
def get_settings() -> Settings:
    return Settings()
