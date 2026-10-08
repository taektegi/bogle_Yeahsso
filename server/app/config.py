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

    # OpenAI (캐릭터 그림·얼굴 위치·소개 문구·대화·검열). 서버에서만 쓰는 비밀이다 (NFR-03).
    openai_api_key: SecretStr | None = None
    # 아이 그림을 캐릭터로 바꾸는 모델. 투명 배경 PNG를 낼 수 있어야 한다.
    openai_image_model: str = "gpt-image-1"
    openai_image_quality: str = "medium"
    # 그림을 보고 얼굴 위치를 말하는 모델, 소개 문구·대화 모델 (이미지 입력과 JSON 출력 지원)
    openai_vision_model: str = "gpt-4.1-mini"
    openai_chat_model: str = "gpt-4.1-mini"
    openai_moderation_model: str = "omni-moderation-latest"

    # 캐릭터 그림을 만드는 방식. openai: OpenAI 이미지 모델 / passthrough: 아이 그림을 그대로
    # 다듬어 쓴다 (OpenAI 키 없이 개발·시연할 때). 어느 쪽이든 후처리와 얼굴 지도는 같다.
    generation_provider: str = "openai"
    # 생성 작업 최대 시간(초)과 동시에 처리할 작업 수. API 계약: 4분
    generation_timeout_seconds: int = 240
    generation_workers: int = 2
    # 작업을 찾는 간격(초). 0이면 생성·모션 작업 처리기를 돌리지 않는다 (테스트).
    worker_poll_seconds: float = 1.0

    # 그림 모션 서버(Animated Drawings, 앱 저장소의 motion_server). 비우면 모션 클립 없이
    # 앱 기본 모션만 쓴다.
    motion_service_url: str = ""
    # 모션 작업 최대 시간(초)과 일시 오류 재시도 횟수. API 계약: 5분, 2번
    motion_timeout_seconds: int = 300
    motion_retries: int = 2

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
