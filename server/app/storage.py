"""Supabase Storage: 서명 URL 만들기, 파일 업로드·삭제 (FR-01.5, FR-06.3).

파일은 비공개 bucket에 있고, 앱에는 서버가 만든 만료되는 서명 URL로만 준다.
`service_role` 키로 Storage REST API를 부른다. 이 키는 서버 밖으로 나가면 안 된다 (NFR-03).
"""

import logging
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from functools import lru_cache
from typing import Annotated, Protocol
from urllib.parse import quote

import httpx2
from fastapi import Depends

from app.config import Settings, get_settings
from app.errors import service_unavailable

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class SignedUrl:
    url: str
    expires_at: datetime


class StorageError(Exception):
    """Storage 작업 실패. 호출하는 쪽이 상황에 맞게 503으로 바꾸거나 기록하고 넘어간다."""


class StorageClient(Protocol):
    def sign(self, paths: Sequence[str]) -> dict[str, SignedUrl]:
        """객체 경로마다 서명 URL을 만든다. 없는 객체는 결과에서 빠진다.

        Storage 요청 자체가 실패하면 StorageError.
        """
        ...

    def upload(self, path: str, data: bytes, content_type: str) -> None:
        """객체를 올린다. 같은 경로가 있으면 덮어쓴다. 실패하면 StorageError."""
        ...

    def download(self, path: str) -> bytes:
        """객체를 내려받는다. 없거나 요청이 실패하면 StorageError."""
        ...

    def remove(self, paths: Sequence[str]) -> None:
        """객체를 삭제한다. 이미 없는 객체는 무시한다. 요청이 실패하면 StorageError."""
        ...


class SupabaseStorage:
    def __init__(
        self,
        *,
        supabase_url: str,
        service_role_key: str,
        bucket: str,
        ttl_seconds: int,
        client: httpx2.Client | None = None,
        clock: Callable[[], datetime] = lambda: datetime.now(UTC),
    ) -> None:
        self._storage_url = f"{supabase_url.rstrip('/')}/storage/v1"
        self._bucket = bucket
        self._ttl_seconds = ttl_seconds
        self._headers = {"Authorization": f"Bearer {service_role_key}", "apikey": service_role_key}
        self._client = client or httpx2.Client(timeout=5.0)
        self._clock = clock

    def sign(self, paths: Sequence[str]) -> dict[str, SignedUrl]:
        unique_paths = list(dict.fromkeys(paths))
        if not unique_paths:
            return {}

        expires_at = self._clock() + timedelta(seconds=self._ttl_seconds)
        try:
            # 경로 여러 개를 한 번에 서명한다. 목록 한 번에 요청 한 번만 쓴다.
            response = self._client.post(
                f"{self._storage_url}/object/sign/{self._bucket}",
                headers=self._headers,
                json={"expiresIn": self._ttl_seconds, "paths": unique_paths},
            )
        except httpx2.HTTPError as exc:
            raise StorageError(f"storage request failed: {type(exc).__name__}") from None
        if response.status_code != 200:
            raise StorageError(f"storage returned HTTP {response.status_code}")

        signed: dict[str, SignedUrl] = {}
        unsigned: set[str] = set()
        for item in response.json():
            signed_path = item.get("signedURL")
            if item.get("error") or not signed_path:
                # 파일이 없거나 접근할 수 없는 객체는 HTTP 200 안에 항목별 오류로 온다.
                # 하나 때문에 나머지를 막지 않도록 결과에서 빼고 호출한 쪽이 처리한다.
                unsigned.add(item.get("path"))
                continue
            signed[item["path"]] = SignedUrl(
                url=f"{self._storage_url}{signed_path}", expires_at=expires_at
            )
        # 응답에 아예 없는 경로는 Storage가 이상하게 동작한 것이므로 실패로 본다.
        missing = set(unique_paths) - signed.keys() - unsigned
        if missing:
            raise StorageError(f"storage did not answer for {len(missing)} path(s)")
        if unsigned:
            logger.warning("storage could not sign %d object(s); skipping them", len(unsigned))
        return signed

    def upload(self, path: str, data: bytes, content_type: str) -> None:
        try:
            response = self._client.post(
                f"{self._storage_url}/object/{self._bucket}/{quote(path)}",
                headers={**self._headers, "Content-Type": content_type, "x-upsert": "true"},
                content=data,
            )
        except httpx2.HTTPError as exc:
            raise StorageError(f"storage request failed: {type(exc).__name__}") from None
        if response.status_code != 200:
            raise StorageError(f"storage returned HTTP {response.status_code}")

    def download(self, path: str) -> bytes:
        try:
            response = self._client.get(
                f"{self._storage_url}/object/{self._bucket}/{quote(path)}",
                headers=self._headers,
                timeout=30.0,
            )
        except httpx2.HTTPError as exc:
            raise StorageError(f"storage request failed: {type(exc).__name__}") from None
        if response.status_code != 200:
            raise StorageError(f"storage returned HTTP {response.status_code}")
        return response.content

    def remove(self, paths: Sequence[str]) -> None:
        unique_paths = list(dict.fromkeys(paths))
        if not unique_paths:
            return
        try:
            response = self._client.request(
                "DELETE",
                f"{self._storage_url}/object/{self._bucket}",
                headers=self._headers,
                json={"prefixes": unique_paths},
            )
        except httpx2.HTTPError as exc:
            raise StorageError(f"storage request failed: {type(exc).__name__}") from None
        # 이미 없는 객체는 응답 목록에서 빠질 뿐 오류가 아니다. 200이면 성공으로 본다.
        if response.status_code != 200:
            raise StorageError(f"storage returned HTTP {response.status_code}")


@lru_cache
def _supabase_storage(
    supabase_url: str, service_role_key: str, bucket: str, ttl_seconds: int
) -> SupabaseStorage:
    return SupabaseStorage(
        supabase_url=supabase_url,
        service_role_key=service_role_key,
        bucket=bucket,
        ttl_seconds=ttl_seconds,
    )


def get_storage(settings: Annotated[Settings, Depends(get_settings)]) -> StorageClient:
    if not settings.supabase_url or settings.supabase_service_role_key is None:
        logger.error("SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is not set")
        raise service_unavailable()
    return _supabase_storage(
        settings.supabase_url,
        settings.supabase_service_role_key.get_secret_value(),
        settings.storage_bucket,
        settings.signed_url_ttl_seconds,
    )


StorageDep = Annotated[StorageClient, Depends(get_storage)]
