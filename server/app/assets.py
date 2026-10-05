"""이미지 에셋을 앱에 내려 줄 때의 공통 모양 (API 계약 3.1절).

모든 이미지는 안정적인 `assetId`와 만료되는 서명 URL을 한 객체로 묶어 내려 준다.
친구·생성 작업·모션 등 이미지를 돌려주는 API는 모두 이 모듈을 쓴다.
"""

import logging
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.errors import service_unavailable
from app.schemas import CamelModel
from app.storage import StorageClient, StorageError

logger = logging.getLogger(__name__)


class ImageRef(CamelModel):
    asset_id: UUID
    url: str
    expires_at: datetime
    content_type: str
    width: int
    height: int


@dataclass(frozen=True)
class AssetRow:
    """`public.assets` 한 행에서 앱에 내려 주는 데에 필요한 값."""

    id: UUID
    storage_path: str
    content_type: str
    width: int
    height: int


def image_refs(storage: StorageClient, assets: Iterable[AssetRow]) -> dict[UUID, ImageRef]:
    """에셋들의 서명 URL을 한 번에 만들어 `{assetId: ImageRef}`로 돌려준다.

    Storage 요청이 실패하면 503(retryable)이다. 파일이 없어 서명하지 못한 에셋은 결과에서 빠지니,
    필요한 에셋이 있는지는 호출한 쪽이 확인한다.
    """
    unique = {asset.id: asset for asset in assets}
    try:
        signed = storage.sign([asset.storage_path for asset in unique.values()])
    except StorageError as exc:
        logger.error("could not sign asset urls: %s", exc)
        raise service_unavailable() from None
    return {
        asset_id: ImageRef(
            asset_id=asset.id,
            url=signed[asset.storage_path].url,
            expires_at=signed[asset.storage_path].expires_at,
            content_type=asset.content_type,
            width=asset.width,
            height=asset.height,
        )
        for asset_id, asset in unique.items()
        if asset.storage_path in signed
    }
