"""Supabase 액세스 토큰 검증 (FR-01.3).

사용자 ID는 **검증된 토큰의 `sub`에서만** 얻는다. 요청 본문·쿼리의 사용자 ID는 쓰지 않는다.
라우터에서는 `CurrentUserDep`을 인자로 받아 쓴다.

    @router.get("/friends")
    def list_friends(user: CurrentUserDep): ...

토큰 서명 방식은 Supabase 프로젝트 설정에 따라 둘 중 하나다.
- 비대칭 키(ES256/RS256): `SUPABASE_URL`의 JWKS에서 공개 키를 받아 검증한다.
- 레거시 공유 비밀(HS256): `SUPABASE_JWT_SECRET`으로 검증한다.
헤더의 alg로 어떤 키를 쓸지 고르되, 허용 목록 밖의 alg(`none` 포함)는 거부한다.
"""

import logging
from dataclasses import dataclass
from functools import lru_cache
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from app.config import Settings, get_settings
from app.errors import ApiError

logger = logging.getLogger(__name__)

AUDIENCE = "authenticated"
_SYMMETRIC_ALGORITHMS = {"HS256"}
_ASYMMETRIC_ALGORITHMS = {"ES256", "RS256"}

_bearer = HTTPBearer(auto_error=False, description="Supabase 로그인 액세스 토큰")


@dataclass(frozen=True)
class CurrentUser:
    id: UUID


def _unauthenticated(message: str = "로그인이 필요해요.") -> ApiError:
    return ApiError(401, "unauthenticated", message, headers={"WWW-Authenticate": "Bearer"})


@lru_cache
def _get_jwks_client(jwks_url: str) -> PyJWKClient:
    return PyJWKClient(jwks_url, cache_keys=True, lifespan=600)


def _signing_key(token: str, algorithm: object, settings: Settings) -> object | None:
    if algorithm in _SYMMETRIC_ALGORITHMS:
        secret = settings.supabase_jwt_secret
        return secret.get_secret_value() if secret else None
    if algorithm in _ASYMMETRIC_ALGORITHMS and settings.jwks_url:
        return _get_jwks_client(settings.jwks_url).get_signing_key_from_jwt(token).key
    return None


def decode_access_token(token: str, settings: Settings) -> dict:
    invalid = "로그인이 만료됐거나 올바르지 않아요. 다시 로그인해 주세요."
    try:
        algorithm = jwt.get_unverified_header(token).get("alg")
        key = _signing_key(token, algorithm, settings)
        if key is None:
            logger.warning("no verification key configured for alg=%s", algorithm)
            raise _unauthenticated(invalid)
        return jwt.decode(
            token,
            key,
            algorithms=[algorithm],
            audience=AUDIENCE,
            issuer=settings.issuer,
            options={"require": ["exp", "sub"]},
        )
    except jwt.PyJWKClientError as exc:
        logger.warning("could not load signing key: %s", type(exc).__name__)
        raise _unauthenticated(invalid) from None
    except jwt.PyJWTError as exc:
        logger.info("token rejected: %s", type(exc).__name__)
        raise _unauthenticated(invalid) from None


# 동기 함수라서 FastAPI가 스레드풀에서 실행한다. (JWKS 최초 조회가 네트워크 호출이다.)
def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> CurrentUser:
    if credentials is None:
        raise _unauthenticated()
    claims = decode_access_token(credentials.credentials, settings)
    try:
        return CurrentUser(id=UUID(str(claims["sub"])))
    except ValueError:
        raise _unauthenticated(
            "로그인이 만료됐거나 올바르지 않아요. 다시 로그인해 주세요."
        ) from None


CurrentUserDep = Annotated[CurrentUser, Depends(get_current_user)]
