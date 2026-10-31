"""실제 Dart·HTTP·Supabase로 이미지 주소 만료를 검증한다. 유료 AI는 호출하지 않는다.

운영 설정·스키마를 바꾸지 않고 전용 임시 계정과 합성 성공 작업만 사용한다.
Flutter는 시스템 TEMP에 복사한 소스에서 실행한다. 비밀값·URL·원문 오류는 출력하지 않는다.
"""

import io
import json
import logging
import os
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID, uuid4

import httpx2
import uvicorn
from PIL import Image, ImageDraw

from app.config import get_settings
from app.db import create_database
from app.friend_settings import SaveFriendIn
from app.main import create_app
from app.repositories.creation import CreationRepository
from app.storage import SupabaseStorage, get_storage

ROOT = Path(__file__).resolve().parents[2]
PROJECT = "https://nylnbctmhdfxswsgxmid.supabase.co"
OUTPUT = ROOT / "output/diagnosis/signed-url-lifecycle.json"


def require(condition, stage):
    if not condition:
        raise RuntimeError(stage)


def main():
    if OUTPUT.exists():
        raise SystemExit("기존 증거를 보존하기 위해 중단했어.")
    logging.disable(logging.CRITICAL)
    result = {"paidAiCalls": 0, "syntheticGenerationFixture": True, "diagnosticTtlSeconds": 4}
    database = admin = storage = user = server = thread = temporary = listener = None
    paths = []
    phase = "configuration"
    try:
        settings = get_settings()
        require(settings.supabase_url.rstrip("/") == PROJECT, "wrong_project")
        flutter = ROOT.parent / ".tools/flutter/bin/flutter.bat"
        require(flutter.is_file(), "flutter_not_found")
        temporary = Path(tempfile.mkdtemp(prefix="bogle-signed-url-"))
        project = temporary / "frontend"
        project.mkdir()
        for folder in ("lib", "assets"):
            shutil.copytree(ROOT / "frontend" / folder, project / folder)
        for name in ("pubspec.yaml", "pubspec.lock"):
            shutil.copyfile(ROOT / "frontend" / name, project / name)
        (project / "test").mkdir()
        shutil.copyfile(
            ROOT / "frontend/test/signed_url_lifecycle_live_test.dart",
            project / "test/signed_url_lifecycle_live_test.dart",
        )
        env = {**os.environ, "PUB_CACHE": str(ROOT.parent / ".tools/pub-cache")}
        phase = "offline_dependencies"
        pub = subprocess.run(
            [str(flutter), "pub", "get", "--offline"],
            cwd=project,
            env=env,
            capture_output=True,
            timeout=120,
        )
        require(pub.returncode == 0, "offline_dependencies")
        result["originalFrontendUntouched"] = True
        print("진단용 Flutter 의존성 준비 완료", flush=True)

        phase = "temporary_account"
        database = create_database(settings)
        key = settings.supabase_service_role_key.get_secret_value()
        admin = httpx2.Client(headers={"Authorization": f"Bearer {key}", "apikey": key}, timeout=20)
        credentials = {
            "email": f"bogle-diag-{uuid4().hex}@example.com",
            "password": secrets.token_urlsafe(32),
        }
        response = admin.post(
            PROJECT + "/auth/v1/admin/users", json={**credentials, "email_confirm": True}
        )
        require(response.status_code == 200, "create_user")
        user = UUID(response.json()["id"])
        response = admin.post(PROJECT + "/auth/v1/token?grant_type=password", json=credentials)
        require(response.status_code == 200, "login")
        access = response.json()["access_token"]
        storage = SupabaseStorage(
            supabase_url=settings.supabase_url,
            service_role_key=key,
            bucket=settings.storage_bucket,
            ttl_seconds=4,
        )
        phase = "synthetic_fixture"
        image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(image).ellipse((45, 25, 210, 220), fill=(230, 165, 180, 255))
        buffer = io.BytesIO()
        image.save(buffer, "PNG")
        data = buffer.getvalue()
        image_path = temporary / "expected.png"
        image_path.write_bytes(data)
        repo = CreationRepository(database)
        assets = []
        for kind in ("source", "art", "thumbnail"):
            asset = repo.add_asset(user, kind, data, "image/png", 256, 256)
            paths.append(asset.storage_path)
            require(asset.storage_path.startswith(f"{user}/"), "fixture_owner")
            storage.upload(asset.storage_path, data, "image/png")
            assets.append(asset.id)
        job_id = uuid4()
        with database.connection() as conn:
            conn.execute(
                "insert into generation_jobs(id,user_id,source_asset_id,source_type,status,"
                "idempotency_key,request_fingerprint,model,prompt_version,art_asset_id,"
                "thumbnail_asset_id,accent_argb,finished_at) "
                "values(%s,%s,%s,'drawing','succeeded',%s,'signed-url-diagnostic',"
                "'synthetic-no-ai','diagnostic',%s,%s,4293297588,now())",
                (job_id, user, assets[0], str(uuid4()), assets[1], assets[2]),
            )
        character, _ = repo.save_friend(
            user,
            SaveFriendIn(
                generation_job_id=job_id,
                name="주소진단",
                personality_type="imaginative",
                favorite_things=["그림"],
                speech_style="해요체",
            ),
            str(uuid4()),
        )

        @asynccontextmanager
        async def lifespan(app):
            app.state.database = database
            yield

        app = create_app()
        app.router.lifespan_context = lifespan  # 전역 워커·자동 정리를 시작하지 않는다.
        app.dependency_overrides[get_storage] = lambda: storage
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
        server = uvicorn.Server(
            uvicorn.Config(app, host="127.0.0.1", port=port, access_log=False, log_config=None)
        )
        thread = threading.Thread(target=server.run, kwargs={"sockets": [listener]}, daemon=True)
        thread.start()
        phase = "server_start"
        deadline = time.monotonic() + 15
        while not server.started and thread.is_alive() and time.monotonic() < deadline:
            time.sleep(0.05)
        require(server.started, "server_start")

        phase = "dart_lifecycle"
        print("실제 Dart·HTTP·Storage 만료 검증 시작", flush=True)
        dart_result = temporary / "dart-result.json"
        env.update(
            {
                "BOGLE_DIAG_API_URL": f"http://127.0.0.1:{port}",
                "BOGLE_DIAG_ACCESS_TOKEN": access,
                "BOGLE_DIAG_FRIEND_ID": str(character),
                "BOGLE_DIAG_JOB_ID": str(job_id),
                "BOGLE_DIAG_IMAGE_PATH": str(image_path),
                "BOGLE_DIAG_RESULT_PATH": str(dart_result),
            }
        )
        run = subprocess.run(
            [str(flutter), "test", "--no-pub", "test/signed_url_lifecycle_live_test.dart"],
            cwd=project,
            env=env,
            capture_output=True,
            timeout=240,
        )
        if dart_result.exists():
            # 이 파일에는 위 진단 테스트가 기록한 불리언·단계 이름·HTTP 상태만 들어간다.
            result["dart"] = json.loads(dart_result.read_text(encoding="utf-8"))
        result["flutterExitCode"] = run.returncode
        require(run.returncode == 0 and dart_result.exists(), "dart_lifecycle")
        result["passed"] = True
    except Exception as error:
        result.update({"failedStage": phase, "errorType": type(error).__name__})
    finally:
        if server:
            server.should_exit = True
        if thread:
            thread.join(timeout=15)
        if listener:
            listener.close()
        result["diagnosticServerStopped"] = thread is None or not thread.is_alive()
        cleaned = True
        if user:
            try:
                require(all(path.startswith(f"{user}/") for path in paths), "cleanup_owner")
                if paths:
                    storage.remove(paths)
                require(
                    admin.delete(PROJECT + f"/auth/v1/admin/users/{user}").status_code == 200,
                    "cleanup_account",
                )
                with database.connection() as conn:
                    row = conn.execute(
                        "select count(*) as n from auth.users where id=%s", (user,)
                    ).fetchone()
                require(row["n"] == 0, "cleanup_verification")
            except Exception:
                cleaned = False
        result["testDataCleaned"] = cleaned
        if database:
            database.close()
        if admin:
            admin.close()
        if temporary:
            resolved = temporary.resolve()
            parent = Path(tempfile.gettempdir()).resolve()
            require(
                resolved.parent == parent and resolved.name.startswith("bogle-signed-url-"),
                "cleanup_temp_path",
            )
            shutil.rmtree(resolved)
        result["temporaryProjectCleaned"] = temporary is None or not temporary.exists()
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(result, ensure_ascii=True))
    if not result.get("passed") or not cleaned or not result["diagnosticServerStopped"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
