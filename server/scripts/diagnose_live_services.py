"""승인한 소수의 실제 AI 호출과 전용 Supabase 임시 계정으로 서버를 확인한다.

개발 설정은 프로그램 내부에서만 읽는다. 키·토큰·URL·외부 본문은 출력하지 않는다.
작업 전체를 스캔하는 워커·복구·자동 정리는 시작하지 않는다.
"""

import argparse
import asyncio
import io
import json
import logging
import secrets
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4

import httpx2
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.config import get_settings
from app.db import create_database
from app.face_analysis import build_face_analyzer
from app.generation_worker import GenerationWorker
from app.image_provider import OpenRouterImages
from app.images import character_image
from app.main import create_app
from app.repositories.creation import CreationRepository
from app.sleep import sleep_status
from app.storage import get_storage

PROJECT_URL = "https://nylnbctmhdfxswsgxmid.supabase.co"
OUTPUT = Path(__file__).resolve().parents[2] / "output/diagnosis"


class CheckFailed(Exception):
    pass


def require(condition, stage):
    if not condition:
        raise CheckFailed(stage)


def sample(kind):
    image = Image.new("RGB", (256, 256), "white")
    draw = ImageDraw.Draw(image)
    draw.ellipse((45, 25, 210, 220), fill=(230, 165, 180), outline="black", width=3)
    draw.ellipse((90, 85, 105, 100), fill="black")
    draw.ellipse((150, 85, 165, 100), fill="black")
    draw.arc((100, 120, 155, 165), 0, 180, fill="black", width=3)
    data = io.BytesIO()
    image.save(data, "JPEG" if kind == "photo" else "PNG")
    return data.getvalue()


class Budget:
    def __init__(self):
        OUTPUT.mkdir(parents=True, exist_ok=True)
        self.path = OUTPUT / "live-budget.json"
        # 기존 실행을 무심코 다시 실행해 과금하지 않게 한다.
        with self.path.open("x", encoding="utf-8") as file:
            file.write("{}")
        self.counts = {"image": 0, "face": 0, "chat": 0}
        self.save()

    def save(self):
        self.path.write_text(json.dumps(self.counts, indent=2), encoding="utf-8")

    def use(self, kind):
        require(self.counts[kind] < 2, "paid_budget_exhausted")
        self.counts[kind] += 1
        self.save()


class CountImages:
    def __init__(self, settings, budget):
        self.actual = OpenRouterImages(settings)
        self.budget = budget

    async def generate(self, reference):
        self.budget.use("image")
        return await self.actual.generate(reference)


class CountFace:
    def __init__(self, actual, budget):
        self.actual, self.budget = actual, budget

    def analyze(self, *args, **kwargs):
        if self.actual is None:
            return None
        self.budget.use("face")
        return self.actual.analyze(*args, **kwargs)


async def process_one(worker, job):
    async def renew():
        while True:
            await asyncio.sleep(5)
            require(await asyncio.to_thread(worker.repo.acquire_lease, worker.owner), "lease_lost")

    heartbeat = asyncio.create_task(renew())
    try:
        await worker.process(job)
    finally:
        heartbeat.cancel()
        try:
            await heartbeat
        except asyncio.CancelledError:
            pass


def main(sources=("drawing", "photo"), *, skip_chat=False, require_generation=False):
    logging.disable(logging.CRITICAL)
    budget = Budget()
    result = {"cases": [], "syntheticChatFixture": False, "testDataCleaned": False}
    settings = database = admin = storage = worker = None
    users = []
    phase = "settings"
    try:
        settings = get_settings()
        require(settings.supabase_url.rstrip("/") == PROJECT_URL, "wrong_project")
        require(settings.database_url and settings.supabase_service_role_key, "server_config")
        require(settings.openrouter_api_key, "image_config")
        database = create_database(settings)
        storage = get_storage(settings)
        key = settings.supabase_service_role_key.get_secret_value()
        admin = httpx2.Client(headers={"Authorization": "Bearer " + key, "apikey": key}, timeout=20)
        phase = "create_test_accounts"
        tokens = []
        for _ in range(2):
            email, password = f"bogle-diag-{uuid4().hex}@example.com", secrets.token_urlsafe(32)
            response = admin.post(
                PROJECT_URL + "/auth/v1/admin/users",
                json={"email": email, "password": password, "email_confirm": True},
            )
            require(response.status_code == 200, "create_test_user")
            users.append(UUID(response.json()["id"]))
            response = admin.post(
                PROJECT_URL + "/auth/v1/token?grant_type=password",
                json={"email": email, "password": password},
            )
            require(response.status_code == 200, "test_login")
            tokens.append(response.json()["access_token"])
        result["authLogin"] = True

        application = create_app()

        @asynccontextmanager
        async def lifespan(app):
            app.state.database = database
            yield  # 운영 워커·복구·정리를 절대 시작하지 않는다.

        application.router.lifespan_context = lifespan
        worker = GenerationWorker(
            database,
            storage,
            settings,
            CountImages(settings, budget),
            CountFace(build_face_analyzer(settings), budget),
        )
        repo = CreationRepository(database)
        headers = {"Authorization": "Bearer " + tokens[0]}
        other_headers = {"Authorization": "Bearer " + tokens[1]}
        saved = []
        phase = "server_endpoints"
        with TestClient(application, raise_server_exceptions=False) as client:
            require(client.get("/v1/me", headers=headers).status_code == 200, "jwt_verification")
            result["jwtVerifiedByServer"] = True
            require(repo.acquire_lease(worker.owner), "generation_worker_busy")
            for kind in sources:
                case = {"sourceType": kind}
                phase = f"{kind}_upload"
                mime = "image/jpeg" if kind == "photo" else "image/png"
                response = client.post(
                    "/v1/assets",
                    headers=headers,
                    files={"file": ("diagnostic", sample(kind), mime)},
                )
                require(response.status_code == 201, "upload")
                asset = response.json()
                require(httpx2.get(asset["url"], timeout=10).status_code == 200, "signed_source")
                case["uploadAndSignedRead"] = True
                response = client.post(
                    "/v1/generations",
                    headers={**headers, "Idempotency-Key": str(uuid4())},
                    json={"sourceAssetId": asset["assetId"], "sourceType": kind},
                )
                require(response.status_code == 202, "enqueue")
                job_id = UUID(response.json()["jobId"])
                # 이 실행에서 만든 작업 한 건만 claim한다. 다른 계정의 큐는 읽지 않는다.
                with database.connection() as conn:
                    job = conn.execute(
                        "update generation_jobs set status='processing',"
                        "started_at=now(),worker_owner=%s where id=%s and user_id=%s "
                        "and status='queued' returning *",
                        (worker.owner, job_id, users[0]),
                    ).fetchone()
                require(job is not None, "scoped_claim")
                phase = f"{kind}_generation"
                asyncio.run(process_one(worker, job))
                response = client.get(f"/v1/generations/{job_id}", headers=headers)
                require(response.status_code == 200, "poll")
                generated = response.json()
                case["status"] = generated["status"]
                if generated["status"] != "succeeded":
                    case["errorCode"] = (generated.get("error") or {}).get("code")
                    case["retryable"] = (generated.get("error") or {}).get("retryable")
                    result["cases"].append(case)
                    continue
                case["facePresent"] = generated.get("face") is not None
                for field in ("art", "thumbnail"):
                    image = httpx2.get(generated[field]["url"], timeout=15)
                    require(image.status_code == 200, "signed_result")
                    with Image.open(io.BytesIO(image.content)) as decoded:
                        require(decoded.format == "PNG", "png_result")
                    (OUTPUT / f"{kind}-{field}.png").write_bytes(image.content)
                    if field == "art":
                        validated = character_image(image.content)
                        require(validated.accent_argb == generated["accentArgb"], "accent_color")
                        case["transparentPngValidated"] = True
                        case["width"], case["height"] = validated.width, validated.height
                case["signedResultDownloads"] = True
                body = {
                    "generationJobId": str(job_id),
                    "name": "진단친구",
                    "personalityType": "imaginative",
                    "favoriteThings": ["그림"],
                    "speechStyle": "해요체",
                }
                save_headers = {**headers, "Idempotency-Key": str(uuid4())}
                first = client.post("/v1/characters", headers=save_headers, json=body)
                require(first.status_code == 201, "save_friend")
                replay = client.post("/v1/characters", headers=save_headers, json=body)
                require(
                    replay.status_code == 200 and replay.json()["id"] == first.json()["id"],
                    "friend_replay",
                )
                saved.append(first.json()["id"])
                case["saveAndReplay"] = True
                result["cases"].append(case)

            if require_generation:
                require(len(saved) == len(sources), "generation_not_succeeded")

            # 이미지 제공자가 실패해도 대화는 별도의 합성 테스트 친구로 확인할 수 있다.
            if not saved:
                phase = "synthetic_chat_fixture"
                asset_ids = []
                for kind in ("source", "art", "thumbnail"):
                    data = sample("drawing")
                    row = repo.add_asset(users[0], kind, data, "image/png", 256, 256)
                    storage.upload(row.storage_path, data, "image/png")
                    asset_ids.append(row.id)
                fixture_job, _ = repo.enqueue(users[0], asset_ids[0], "drawing", str(uuid4()))
                with database.connection() as conn:
                    conn.execute(
                        "update generation_jobs set status='succeeded',art_asset_id=%s,"
                        "thumbnail_asset_id=%s,accent_argb=4289974783 where id=%s and user_id=%s",
                        (asset_ids[1], asset_ids[2], fixture_job["id"], users[0]),
                    )
                first = client.post(
                    "/v1/characters",
                    headers={**headers, "Idempotency-Key": str(uuid4())},
                    json={
                        "generationJobId": str(fixture_job["id"]),
                        "name": "대화검증친구",
                        "personalityType": "gentle_smiling",
                        "favoriteThings": ["그림"],
                        "speechStyle": "해요체",
                    },
                )
                require(first.status_code == 201, "fixture_friend_save")
                saved.append(first.json()["id"])
                result["syntheticChatFixture"] = True

            phase = "ownership_chat_delete"
            friend = saved[0]
            require(
                client.get(f"/v1/characters/{friend}", headers=other_headers).status_code == 404,
                "ownership",
            )
            result["ownershipBlocked"] = True
            if skip_chat:
                result["chat"] = {"skipped": "not_in_scope"}
            elif sleep_status(datetime.now(UTC)).asleep:
                result["chat"] = {"skipped": "server_sleep_window"}
            elif not settings.openai_api_key:
                result["chat"] = {"skipped": "moderation_not_configured"}
            else:
                result["chat"] = []
                for message in ("안녕", "그림 그리는 걸 좋아해?"):
                    budget.use("chat")
                    body = {"clientMessageId": str(uuid4()), "text": message}
                    response = client.post(
                        f"/v1/characters/{friend}/messages", headers=headers, json=body
                    )
                    require(response.status_code == 200, "chat_status")
                    reply = response.json()
                    replay = client.post(
                        f"/v1/characters/{friend}/messages", headers=headers, json=body
                    )
                    require(
                        replay.status_code == 200
                        and replay.json()["assistantMessage"]["id"]
                        == reply["assistantMessage"]["id"],
                        "chat_replay",
                    )
                    result["chat"].append(
                        {"source": reply["assistantMessage"].get("source"), "sameReply": True}
                    )
            for friend in saved:
                require(
                    client.delete(f"/v1/characters/{friend}", headers=headers).status_code == 204,
                    "delete_friend",
                )
                require(
                    client.get(f"/v1/characters/{friend}/messages", headers=headers).status_code
                    == 404,
                    "delete_history",
                )
            result["deleteAndHistory"] = True
    except Exception as exc:
        result["failedStage"] = str(exc) if isinstance(exc, CheckFailed) else phase
        result["errorType"] = type(exc).__name__
    finally:
        if worker is not None:
            try:
                worker.repo.release_lease(worker.owner)
            except Exception:
                result["leaseCleanupFailed"] = True
        cleaned = True
        for user in users:
            try:
                with database.connection() as conn:
                    paths = [
                        row["storage_path"]
                        for row in conn.execute(
                            "select storage_path from public.assets where user_id=%s", (user,)
                        ).fetchall()
                    ]
                if paths:
                    require(all(path.startswith(f"{user}/") for path in paths), "cleanup_owner")
                    storage.remove(paths)
                deleted = admin.delete(PROJECT_URL + f"/auth/v1/admin/users/{user}")
                require(deleted.status_code == 200, "delete_test_account")
            except Exception:
                cleaned = False
        result["testDataCleaned"] = cleaned
        result["paidAttempts"] = budget.counts
        if database:
            database.close()
        if admin:
            admin.close()
        (OUTPUT / "live-services.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(json.dumps(result, ensure_ascii=True, indent=2))
    if require_generation and (
        "failedStage" in result or not result["testDataCleaned"] or result.get("leaseCleanupFailed")
    ):
        raise SystemExit(1)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm-paid-budget", action="store_true", required=True)
    parser.add_argument("--output-dir", type=Path, default=OUTPUT)
    parser.add_argument(
        "--sources", nargs="+", choices=("drawing", "photo"), default=("drawing", "photo")
    )
    parser.add_argument("--skip-chat", action="store_true")
    parser.add_argument("--require-generation", action="store_true")
    args = parser.parse_args()
    OUTPUT = args.output_dir.resolve()
    main(args.sources, skip_chat=args.skip_chat, require_generation=args.require_generation)
