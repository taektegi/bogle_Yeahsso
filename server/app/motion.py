"""친구 그림의 모션 클립 (FR-10).

앱 저장소의 그림 모션 서버(motion_server/, Meta Animated Drawings)에 친구 그림을 보내고,
만들어진 GIF(jump·wave·dance)를 우리 Storage로 옮겨 서명 URL로 내려 준다.

- 입력은 **생성된 캐릭터 그림**(투명 PNG)을 흰 종이에 얹은 것이다. 모션 모델은 흰 종이 위의
  그림으로 학습되어서, 투명 배경 그대로 보내면 사람 모양을 잘 찾지 못한다
  (앱의 drawingAsPng와 같음).
- 모션 서버가 사람 모양으로 인식하지 못하면 `unsupported`(이유 포함)로 끝난다. 앱은 이때 자기
  모션(폴짝·빙그르르·인사·먹기 등 + 얼굴 지도의 눈·입 움직임)을 쓴다.
  실패도 친구 생성 실패가 아니다.
- 일시 오류(연결 실패·5xx)는 최대 `motion_retries`번 다시 시도한다. 전체 한도는 5분이다.
"""

import io
import logging
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol
from uuid import uuid4

import httpx2
from PIL import Image

from app import imaging
from app.repositories.assets import NewAsset
from app.repositories.motions import MotionRepository, MotionWork
from app.storage import StorageClient, StorageError

logger = logging.getLogger(__name__)

CLIPS = ("jump", "wave", "dance")
POLL_SECONDS = 2.0
_PAGE_TARGET = 900  # 앱 drawingAsPng와 같은 크기
_PAGE_PADDING = 40


class MotionServiceError(Exception):
    """모션 서버를 잠시 쓸 수 없음 (다시 시도할 수 있음)."""


class MotionClient(Protocol):
    def submit(self, png: bytes) -> str: ...

    def status(self, remote_id: str) -> dict[str, Any]: ...

    def fetch(self, url: str) -> bytes: ...


class HttpMotionClient:
    def __init__(self, base_url: str, client: httpx2.Client | None = None) -> None:
        self._base = base_url.rstrip("/")
        self._client = client or httpx2.Client(timeout=20.0)

    def _ok(self, response: httpx2.Response) -> httpx2.Response:
        if response.status_code >= 500:
            raise MotionServiceError(f"motion service HTTP {response.status_code}")
        if response.status_code != 200:
            raise ValueError(f"motion service HTTP {response.status_code}")
        return response

    def submit(self, png: bytes) -> str:
        try:
            response = self._client.post(
                f"{self._base}/motions", files={"image": ("drawing.png", png, "image/png")}
            )
        except httpx2.HTTPError as exc:
            raise MotionServiceError(type(exc).__name__) from None
        return str(self._ok(response).json()["id"])

    def status(self, remote_id: str) -> dict[str, Any]:
        try:
            response = self._client.get(f"{self._base}/motions/{remote_id}")
        except httpx2.HTTPError as exc:
            raise MotionServiceError(type(exc).__name__) from None
        return self._ok(response).json()

    def fetch(self, url: str) -> bytes:
        try:
            response = self._client.get(url, timeout=60.0)
        except httpx2.HTTPError as exc:
            raise MotionServiceError(type(exc).__name__) from None
        return self._ok(response).content


def page_for_motion(art_png: bytes) -> bytes:
    """친구 그림을 흰 종이에: 긴 변 900px, 둘레 40px 여백."""
    art = imaging.open_rgba(art_png)
    scale = _PAGE_TARGET / max(art.size)
    art = art.resize(
        (max(1, round(art.width * scale)), max(1, round(art.height * scale))),
        Image.Resampling.LANCZOS,
    )
    page = imaging.flatten_on_white(art, padding=_PAGE_PADDING)
    out = io.BytesIO()
    page.save(out, format="PNG")
    return out.getvalue()


@dataclass(frozen=True)
class _Clip:
    kind: str
    box: list[float]
    data: bytes
    width: int
    height: int


def _box(value: Any) -> list[float] | None:
    if not isinstance(value, list) or len(value) != 4:
        return None
    try:
        box = [min(1.0, max(0.0, float(v))) for v in value]
    except (TypeError, ValueError):
        return None
    return box if box[2] > box[0] and box[3] > box[1] else None


def process_motion(
    work: MotionWork,
    *,
    repo: MotionRepository,
    storage: StorageClient,
    client: MotionClient,
    timeout: float,
    retries: int,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> None:
    """작업 하나를 끝까지 처리한다 (ready / unsupported / failed, 일시 오류면 다시 줄 세움)."""
    job = work.job
    deadline = clock() + timeout
    try:
        remote = job.remote_id
        if remote is None:
            remote = client.submit(page_for_motion(storage.download(work.art_path)))
            repo.set_remote(job.id, remote)
        while True:
            state = client.status(remote)
            status = state.get("status")
            if status == "ready":
                break
            if status == "unsupported":
                repo.finish(job.id, "unsupported", str(state.get("reason") or "unsupported"))
                return
            if status not in ("queued", "working"):
                repo.finish(job.id, "failed", str(state.get("reason") or "") or None)
                return
            if clock() > deadline:
                repo.finish(job.id, "failed", "timeout")
                return
            if not repo.is_working(job.id):
                return  # 친구가 지워졌다
            sleep(POLL_SECONDS)

        clips: list[_Clip] = []
        for kind in CLIPS:
            info = (state.get("clips") or {}).get(kind)
            box = _box(info.get("box")) if isinstance(info, dict) else None
            if not box or not isinstance(info.get("url"), str):
                continue
            data = client.fetch(info["url"])
            with Image.open(io.BytesIO(data)) as gif:
                width, height = gif.size
            clips.append(_Clip(kind, box, data, width, height))
        if not clips:
            repo.finish(job.id, "failed", "no_clips")
            return

        assets: list[NewAsset] = []
        for clip in clips:
            asset_id = uuid4()
            path = f"{job.user_id}/motion/{job.character_id}/{asset_id}.gif"
            storage.upload(path, clip.data, "image/gif")
            assets.append(
                NewAsset(
                    id=asset_id,
                    kind="motion",
                    storage_path=path,
                    content_type="image/gif",
                    byte_size=len(clip.data),
                    width=clip.width,
                    height=clip.height,
                )
            )
        saved = repo.finish_ready(
            job,
            {
                c.kind: {"assetId": str(a.id), "box": c.box}
                for c, a in zip(clips, assets, strict=True)
            },
            assets,
        )
        if not saved:
            storage.remove([a.storage_path for a in assets])
    except (MotionServiceError, StorageError) as exc:
        if job.attempts > retries:
            logger.warning("motion job gave up after %d attempts: %s", job.attempts, exc)
            repo.finish(job.id, "failed", "unavailable")
        else:
            logger.info("motion job will retry: %s", exc)
            sleep(3.0 * job.attempts)
            repo.requeue(job.id)
    except Exception as exc:  # 모션 실패가 다른 작업을 막으면 안 된다
        logger.error("motion job failed: %s", type(exc).__name__, exc_info=exc)
        repo.finish(job.id, "failed", None)
