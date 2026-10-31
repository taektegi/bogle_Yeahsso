"""실제 개발 Supabase에서 새 친구 계약을 검증한다. AI 호출은 하지 않는다.

합성 이미지·자체 생성 작업은 전용 계정에만 만든다. 전역 워커·정리는 시작하지 않는다.
키·로그인 정보·서명 URL은 출력하지 않고 최종 성공 여부만 기록한다.
"""

import io
import json
import logging
import secrets
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from uuid import UUID, uuid4

import httpx2
from fastapi.testclient import TestClient
from PIL import Image, ImageDraw

from app.clock import get_now
from app.config import get_settings
from app.db import create_database
from app.main import create_app
from app.repositories.creation import CreationRepository
from app.repositories.messages import MessageRepository
from app.storage import get_storage
from scripts.diagnose_live_services import OUTPUT, PROJECT_URL, CheckFailed, require


def main():
    logging.disable(logging.CRITICAL)
    output = OUTPUT / "fix-live-friend-sync.json"
    if output.exists():
        raise SystemExit("기존 증거를 보존하기 위해 실행을 중단했어요.")
    result = {"syntheticGenerationFixture": True, "paidAiCalls": 0}
    users, database, admin, storage = [], None, None, None
    phase = "configuration"
    try:
        settings = get_settings()
        require(settings.supabase_url.rstrip("/") == PROJECT_URL, "wrong_project")
        database = create_database(settings)
        storage = get_storage(settings)
        key = settings.supabase_service_role_key.get_secret_value()
        admin = httpx2.Client(headers={"Authorization": "Bearer " + key, "apikey": key}, timeout=20)
        tokens = []
        phase = "temporary_accounts"
        for _ in range(2):
            credentials = {
                "email": f"bogle-diag-{uuid4().hex}@example.com",
                "password": secrets.token_urlsafe(32),
            }
            response = admin.post(
                PROJECT_URL + "/auth/v1/admin/users", json={**credentials, "email_confirm": True}
            )
            require(response.status_code == 200, "create_user")
            users.append(UUID(response.json()["id"]))
            response = admin.post(
                PROJECT_URL + "/auth/v1/token?grant_type=password", json=credentials
            )
            require(response.status_code == 200, "login")
            tokens.append(response.json()["access_token"])

        @asynccontextmanager
        async def lifespan(app):
            app.state.database = database
            yield

        app = create_app()
        app.router.lifespan_context = lifespan
        # 시간 경계 검사는 이 검증 프로세스에만 주입하며 외부 AI를 부르지 않는다.
        app.dependency_overrides[get_now] = lambda: datetime(2026, 10, 31, 12, tzinfo=UTC)
        repo = CreationRepository(database)
        me = {"Authorization": "Bearer " + tokens[0], "X-Bogle-Utc-Offset-Minutes": "540"}
        other = {"Authorization": "Bearer " + tokens[1]}
        image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(image).ellipse((45, 25, 210, 220), fill=(230, 165, 180, 255))
        buffer = io.BytesIO()
        image.save(buffer, "PNG")
        data = buffer.getvalue()
        phase = "synthetic_fixture"
        assets = []
        for kind in ("source", "art", "thumbnail"):
            asset = repo.add_asset(users[0], kind, data, "image/png", 256, 256)
            storage.upload(asset.storage_path, data, "image/png")
            require(storage.download(asset.storage_path) == data, "storage_readback")
            assets.append(asset.id)
        job, _ = repo.enqueue(users[0], assets[0], "drawing", str(uuid4()))
        with database.connection() as conn:
            conn.execute(
                "update generation_jobs set status='succeeded',art_asset_id=%s,"
                "thumbnail_asset_id=%s,accent_argb=4293297588,finished_at=now() "
                "where id=%s and user_id=%s",
                (assets[1], assets[2], job["id"], users[0]),
            )
        with TestClient(app, raise_server_exceptions=False) as client:
            phase = "save"
            body = {
                "generationJobId": str(job["id"]),
                "name": "진단친구",
                "personalityType": "imaginative",
                "favoriteThings": ["그림"],
                "speechStyle": "해요체",
                "bedtime": 1260,
                "wakeTime": 420,
            }
            save_headers = {**me, "Idempotency-Key": str(uuid4())}
            first = client.post("/v1/characters", headers=save_headers, json=body)
            require(first.status_code == 201, "save")
            path = "/v1/characters/" + first.json()["id"]
            again = client.post("/v1/characters", headers=save_headers, json=body)
            require(
                again.status_code == 200 and again.json()["id"] == first.json()["id"], "save_replay"
            )
            result["saveAndReplay"] = True
            phase = "edit"
            edit = {
                "name": "새 이름",
                "personality": "상상을 좋아해요",
                "introduction": "☁️" * 70,
                "speechStyle": "반말",
                "bedtime": 1320,
                "wakeTime": 360,
            }
            require(client.patch(path, headers=me, json=edit).status_code == 200, "edit")
            got = client.get(path, headers=me)
            require(
                got.status_code == 200 and all(got.json()[k] == v for k, v in edit.items()),
                "round_trip",
            )
            profile = MessageRepository(database).get_friend_profile(
                users[0], UUID(first.json()["id"])
            )
            require(
                profile.name == edit["name"] and profile.personality_type == edit["personality"],
                "chat_profile",
            )
            require(
                client.patch(path, headers=other, json={"name": "도용"}).status_code == 404,
                "ownership",
            )
            result.update(
                {"editRoundTrip": True, "chatUsesEditedProfile": True, "otherUserEditBlocked": True}
            )
            phase = "sleep"
            require(
                client.get(path + "/status", headers=me).json()["asleep"] is False, "custom_sleep"
            )
            require(
                client.patch(path, headers=me, json={"bedtime": 1260, "wakeTime": 420}).status_code
                == 200,
                "default_sleep",
            )
            require(
                client.post(
                    path + "/messages",
                    headers=me,
                    json={"clientMessageId": str(uuid4()), "text": "안녕"},
                ).status_code
                == 409,
                "sleep_chat_guard",
            )
            result["sleepBoundaryWithInjectedClock"] = True
            phase = "delete"
            require(client.delete(path, headers=me).status_code == 204, "delete")
            require(client.get(path, headers=me).status_code == 404, "deleted")
            result["deleted"] = True
    except Exception as error:
        result.update(
            {
                "failedStage": str(error) if isinstance(error, CheckFailed) else phase,
                "errorType": type(error).__name__,
            }
        )
    finally:
        cleaned = True
        for user in users:
            try:
                with database.connection() as conn:
                    paths = [
                        r["storage_path"]
                        for r in conn.execute(
                            "select storage_path from assets where user_id=%s", (user,)
                        ).fetchall()
                    ]
                require(all(path.startswith(f"{user}/") for path in paths), "cleanup_owner")
                if paths:
                    storage.remove(paths)
                require(
                    admin.delete(PROJECT_URL + f"/auth/v1/admin/users/{user}").status_code == 200,
                    "cleanup_account",
                )
            except Exception:
                cleaned = False
        result["testDataCleaned"] = cleaned
        if database:
            database.close()
        if admin:
            admin.close()
        output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(result, ensure_ascii=True))
    if "failedStage" in result or not result["testDataCleaned"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
