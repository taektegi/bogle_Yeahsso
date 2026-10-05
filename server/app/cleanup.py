"""미사용 에셋 정리 (FR-04.8, API 계약 8절).

서버가 주기적으로(기본 1시간마다) 아래 에셋의 Storage 파일과 행을 지운다.

1. **삭제를 요청한 에셋**: 친구를 삭제했는데 파일 삭제가 실패해서 남은 것. 나이와 상관없이 지운다.
2. **오래된 미사용 에셋**: 업로드만 하고 친구로 저장하지 않았거나 생성에 실패한 것. 만든 지
   `asset_retention_hours`(기본 24시간)가 지난 것을 지운다.

친구가 쓰고 있는 에셋은 어느 쪽이든 지우지 않는다. 순서는 **파일 먼저, 행 나중**이다. 파일 삭제가
실패하면 행이 남아서 다음 주기에 다시 시도한다.

다른 담당자가 에셋을 가리키는 새 테이블(생성 작업·모션 결과 등)을 만들면 **`ASSET_REFERENCES`에
조건을 추가해야** 한다. 그렇지 않으면 그 테이블이 쓰고 있는 에셋이 24시간 뒤에 지워진다.

주의: 서버 프로세스 1개를 전제로 한다 (요청 횟수 제한과 같다). 여러 개가 동시에 돌아도 같은 파일을
두 번 지울 뿐 안전하지만, 쓸데없이 중복된다.
"""

import asyncio
import contextlib
import logging
from dataclasses import dataclass
from datetime import timedelta

import anyio.to_thread
import psycopg

from app.db import Database
from app.storage import StorageClient, StorageError

logger = logging.getLogger(__name__)

# 에셋(`a`)을 쓰고 있는 곳을 나타내는 SQL 조건. 하나라도 참이면 그 에셋은 지우지 않는다.
# 새 테이블이 에셋을 가리키면 여기에 한 줄을 더한다. 예)
#   "exists (select 1 from public.generation_jobs j"
#   " where j.source_asset_id = a.id and j.status in ('queued', 'processing'))"
ASSET_REFERENCES: list[str] = [
    "exists (select 1 from public.friends f"
    " where f.source_asset_id = a.id or f.art_asset_id = a.id or f.thumbnail_asset_id = a.id)",
]

BATCH_SIZE = 100
MAX_BATCHES_PER_RUN = 20  # 한 번에 최대 2,000개. 나머지는 다음 주기에 이어서 지운다.
FIRST_RUN_DELAY_SECONDS = 60


@dataclass(frozen=True)
class CleanupResult:
    deleted: int = 0
    # 파일 삭제 실패 등으로 이번에 못 지운 것이 있는지 (다음 주기에 다시 시도한다)
    incomplete: bool = False


def _unused_clause() -> str:
    references = " or ".join(ASSET_REFERENCES)
    return f"not ({references})"


def _select_batch(db: Database, retention: timedelta) -> list[tuple]:
    with db.connection() as conn:
        rows = conn.execute(
            "select a.id, a.storage_path from public.assets a"
            " where (a.delete_requested_at is not null or a.created_at < now() - %(retention)s)"
            f" and {_unused_clause()}"
            " order by a.created_at limit %(limit)s",
            {"retention": retention, "limit": BATCH_SIZE},
        ).fetchall()
    return [(row["id"], row["storage_path"]) for row in rows]


def _delete_rows(db: Database, asset_ids: list) -> int:
    # 파일을 지우는 사이에 친구가 에셋을 쓰기 시작했다면(외래 키) 그 행은 지우지 않는다.
    with db.connection() as conn:
        try:
            deleted = conn.execute(
                f"delete from public.assets a where a.id = any(%(ids)s) and {_unused_clause()}",
                {"ids": asset_ids},
            ).rowcount
        except psycopg.errors.ForeignKeyViolation:
            return 0
    return deleted


def cleanup_assets(db: Database, storage: StorageClient, retention: timedelta) -> CleanupResult:
    """미사용 에셋을 한 번 정리한다. 동기 함수라서 스레드에서 실행한다."""
    deleted = 0
    for _ in range(MAX_BATCHES_PER_RUN):
        batch = _select_batch(db, retention)
        if not batch:
            return CleanupResult(deleted=deleted)
        try:
            storage.remove([path for _, path in batch])
        except StorageError as exc:
            # 같은 묶음을 계속 두드리지 않도록 이번 주기는 여기서 멈춘다.
            # 행이 남아 있으니 다음 주기에 다시 시도한다.
            logger.warning("asset cleanup could not remove files, will retry: %s", exc)
            return CleanupResult(deleted=deleted, incomplete=True)
        removed = _delete_rows(db, [asset_id for asset_id, _ in batch])
        deleted += removed
        if removed < len(batch):
            # 일부 행이 그 사이 쓰이기 시작했거나 다른 프로세스가 먼저 지웠다.
            logger.info("asset cleanup skipped %d row(s) that became used", len(batch) - removed)
        if len(batch) < BATCH_SIZE:
            return CleanupResult(deleted=deleted)
    return CleanupResult(deleted=deleted, incomplete=True)


async def run_periodically(
    db: Database,
    storage: StorageClient,
    *,
    interval_seconds: float,
    retention: timedelta,
    first_delay_seconds: float = FIRST_RUN_DELAY_SECONDS,
) -> None:
    """서버가 떠 있는 동안 주기적으로 정리한다. 취소(CancelledError)로 멈춘다.

    한 번 실패해도 서버와 다음 주기는 계속된다. 로그에는 개수와 오류 종류만 남기고
    경로는 남기지 않는다.
    """
    await asyncio.sleep(first_delay_seconds)
    while True:
        try:
            result = await anyio.to_thread.run_sync(cleanup_assets, db, storage, retention)
            if result.deleted or result.incomplete:
                logger.info(
                    "asset cleanup: deleted=%d incomplete=%s", result.deleted, result.incomplete
                )
        except Exception as exc:  # 정리 실패가 서버를 멈추게 하면 안 된다
            logger.error("asset cleanup failed: %s", type(exc).__name__)
        await asyncio.sleep(interval_seconds)


@contextlib.asynccontextmanager
async def background_cleanup(
    db: Database | None,
    storage: StorageClient | None,
    *,
    interval_seconds: float,
    retention: timedelta,
    first_delay_seconds: float = FIRST_RUN_DELAY_SECONDS,
):
    """`async with`로 감싸 두면 블록이 끝날 때(서버 종료) 정리 작업도 함께 멈춘다.

    DB·Storage가 설정되지 않았거나 간격이 0이면 아무것도 하지 않는다.
    """
    if db is None or storage is None or interval_seconds <= 0:
        logger.info("asset cleanup is disabled")
        yield None
        return
    task = asyncio.create_task(
        run_periodically(
            db,
            storage,
            interval_seconds=interval_seconds,
            retention=retention,
            first_delay_seconds=first_delay_seconds,
        )
    )
    try:
        yield task
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
