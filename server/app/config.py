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
    # 서버에서만 쓰는 비밀. 앱에 넣지 않는다 (NFR-03).
    supabase_service_role_key: SecretStr | None = None

    # Postgres 직접 연결 문자열. Supabase 대시보드의 Connection string(pooler)을 쓴다.
    database_url: SecretStr | None = None

    storage_bucket: str = "bogle-media"
    # 앱에 주는 서명 URL의 유효 시간 (초). API 계약: 60분
    signed_url_ttl_seconds: int = 3600

    # 미사용 에셋 정리 (app/cleanup.py). 간격 0이면 정리 작업을 돌리지 않는다.
    cleanup_interval_seconds: int = 3600
    # 업로드하고 친구로 저장하지 않은 에셋을 보관하는 시간. API 계약: 24시간
    asset_retention_hours: int = 24

    # 대화 생성은 OpenRouter, 입력·출력 안전 검사는 OpenAI Moderation을 쓴다 (FR-09).
    # 두 키는 서버에만 두고 앱·로그·응답에 노출하지 않는다 (NFR-03, NFR-09).
    openrouter_api_key: SecretStr | None = None
    openrouter_base_url: str = "https://openrouter.ai/api/v1"
    openrouter_model: str = "openai/gpt-6-luna"
    openai_api_key: SecretStr | None = None
    openai_base_url: str = "https://api.openai.com/v1"
    openai_moderation_model: str = "omni-moderation-latest"
    # 입력 검사부터 출력 검사까지의 전체 한도. 초과하면 스크립트 대사로 대체한다.
    chat_ai_timeout_seconds: float = 15.0

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
