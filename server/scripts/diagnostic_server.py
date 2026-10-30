"""팀 API 진단 전용 HTTP 서버. 운영 앱·인증·스키마는 변경하지 않는다.

로컬 PostgreSQL에 임시 DB를 만들고 실제 라우터와 워커를 실행한다.
Auth·Storage·AI만 진단용 구현이며 외부 서비스에는 접속하지 않는다.
"""

import argparse
import asyncio
import hashlib
import io
import json
import logging
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import jwt
import psycopg
import uvicorn
from fastapi import Request, Response
from PIL import Image, ImageDraw
from psycopg import conninfo
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from app.config import Settings, get_settings

# app.main의 초기화가 개발자의 .env를 읽지 않게 한다. 별도 프로세스에만 적용된다.
Settings.model_config["env_file"] = None

from app.ai_chat import ChatReply, get_chat_ai  # noqa: E402
from app.clock import get_now  # noqa: E402
from app.db import Database  # noqa: E402
from app.generation_worker import GenerationWorker  # noqa: E402
from app.image_provider import GenerationError  # noqa: E402
from app.main import create_app  # noqa: E402
from app.storage import SignedUrl, StorageError, get_storage  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
SECRET = "local-diagnostic-only-20261031-not-a-real-secret"
USERS = [UUID("11111111-1111-4111-8111-111111111111"), UUID("22222222-2222-4222-8222-222222222222")]


def image_bytes(kind="art", shade=180):
    image = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((40, 30, 215, 230), fill=(shade, 140, 190, 255))
    draw.ellipse((90, 90, 105, 105), fill="black")
    draw.ellipse((150, 90, 165, 105), fill="black")
    result = io.BytesIO()
    if kind == "photo":
        image.convert("RGB").save(result, "JPEG")
    else:
        image.save(result, "PNG")
    return result.getvalue()


class DiagnosticStorage:
    def __init__(self, base):
        self.base = base
        self.files = {}
        self.paths = {}
        self.reads = 0

    def upload(self, path, data, content_type):
        self.files[path] = (data, content_type)

    def download(self, path):
        if path not in self.files:
            raise StorageError("diagnostic file missing")
        self.reads += 1
        return self.files[path][0]

    def sign(self, paths):
        result = {}
        for path in paths:
            if path not in self.files:
                continue
            key = hashlib.sha256(path.encode()).hexdigest()
            self.paths[key] = path
            result[path] = SignedUrl(
                f"{self.base}/diagnostic/files/{key}", datetime.now(UTC) + timedelta(hours=1)
            )
        return result

    def remove(self, paths):
        for path in paths:
            self.files.pop(path, None)


class DiagnosticImages:
    def __init__(self):
        self.mode = "success"
        self.calls = 0

    async def generate(self, reference):
        self.calls += 1
        if self.mode == "timeout":
            await asyncio.sleep(5)
        if self.mode == "rejected":
            raise GenerationError("generation_rejected", "진단용 정책 거부", False)
        if self.mode == "invalid_png":
            return b"not-an-image"
        await asyncio.sleep(0.08)
        return image_bytes(shade=100 + hashlib.sha256(reference.encode()).digest()[0] % 120)


class DiagnosticFace:
    def analyze(self, image, *, width, height, content_type):
        from app.face_analysis import validate_face_payload

        return validate_face_payload(
            {
                "version": 1,
                "size": [width, height],
                "facing": "front",
                "head": [40, 30, 176, 200],
                "eyes": [[98, 98, 8], [158, 98, 8]],
                "mouth": [128, 150, 30, 12],
                "cheeks": [],
            },
            width=width,
            height=height,
        )


class DiagnosticChat:
    def reply(self, *, friend, history, user_text, deadline=None):
        return ChatReply(text="함께 이야기해서 기뻐요!", source="script")


def run(port, admin_url):
    parsed = conninfo.conninfo_to_dict(admin_url)
    if parsed.get("host") not in ("127.0.0.1", "localhost"):
        raise ValueError("diagnostic server requires a loopback PostgreSQL")
    name = f"bogle_diag_{uuid4().hex[:12]}"
    url = conninfo.make_conninfo(admin_url, dbname=name)
    with psycopg.connect(admin_url, autocommit=True) as conn:
        conn.execute(f'create database "{name}"')
    database = None
    try:
        with psycopg.connect(url, autocommit=True) as conn:
            conn.execute((ROOT / "tests/sql/supabase_stub.sql").read_text(encoding="utf-8"))
            for migration in sorted((ROOT.parent / "supabase/migrations").glob("*.sql")):
                conn.execute(migration.read_text(encoding="utf-8"))
            for user in USERS:
                conn.execute(
                    "insert into auth.users(id,email) values(%s,%s)",
                    (user, f"{user}@diagnostic.test"),
                )
        pool = ConnectionPool(
            url,
            min_size=1,
            max_size=10,
            kwargs={"row_factory": dict_row, "prepare_threshold": None},
        )
        database = Database(pool)
        base = f"http://127.0.0.1:{port}"
        storage, provider = DiagnosticStorage(base), DiagnosticImages()
        settings = Settings(
            _env_file=None,
            supabase_url=base,
            supabase_jwt_secret=SECRET,
            openrouter_api_key="local-diagnostic-only",
            generation_timeout_seconds=3,
            cleanup_interval_seconds=0,
        )
        application = create_app()
        application.dependency_overrides[get_settings] = lambda: settings
        application.dependency_overrides[get_storage] = lambda: storage
        application.dependency_overrides[get_chat_ai] = lambda: DiagnosticChat()
        # 로컬 테스트에서만 시간을 고정한다. 실제 서비스 시간은 변경하지 않는다.
        clock = {"value": datetime(2026, 10, 31, 3, tzinfo=UTC)}
        application.dependency_overrides[get_now] = lambda: clock["value"]
        worker = GenerationWorker(database, storage, settings, provider, DiagnosticFace())

        @asynccontextmanager
        async def lifespan(app):
            app.state.database = database
            task = asyncio.create_task(worker.run())
            try:
                yield
            finally:
                task.cancel()
                try:
                    await task
                except asyncio.CancelledError:
                    pass

        application.router.lifespan_context = lifespan

        @application.post("/auth/v1/token", include_in_schema=False)
        async def token(request: Request):
            body = await request.json()
            user = USERS[1] if body.get("email", "").startswith("other") else USERS[0]
            access = jwt.encode(
                {
                    "sub": str(user),
                    "aud": "authenticated",
                    "iss": base + "/auth/v1",
                    "exp": datetime.now(UTC) + timedelta(hours=1),
                },
                SECRET,
                algorithm="HS256",
            )
            return {"access_token": access, "refresh_token": "local-only", "expires_in": 3600}

        @application.get("/diagnostic/input/{kind}", include_in_schema=False)
        def input_image(kind: str):
            return Response(
                image_bytes(kind), media_type="image/jpeg" if kind == "photo" else "image/png"
            )

        @application.get("/diagnostic/files/{key}", include_in_schema=False)
        def file(key: str):
            path = storage.paths.get(key)
            if path not in storage.files:
                return Response(status_code=404)
            data, content_type = storage.files[path]
            return Response(data, media_type=content_type)

        @application.post("/diagnostic/control/{mode}", include_in_schema=False)
        def control(mode: str):
            if mode in ("awake", "asleep"):
                clock["value"] = datetime(2026, 10, 31, 14 if mode == "asleep" else 3, tzinfo=UTC)
            elif mode in ("success", "timeout", "rejected", "invalid_png"):
                provider.mode = mode
            else:
                return Response(status_code=400)
            return {"mode": mode}

        @application.get("/diagnostic/observations", include_in_schema=False)
        def observations():
            with database.connection() as conn:
                return {
                    "jobs": conn.execute("select count(*) as n from generation_jobs").fetchone()[
                        "n"
                    ],
                    "friends": conn.execute("select count(*) as n from friends").fetchone()["n"],
                    "aiCalls": provider.calls,
                    "storageReadbacks": storage.reads,
                }

        output = ROOT.parent / "output/diagnosis"
        output.mkdir(parents=True, exist_ok=True)
        # 운영 공개 명세만 저장한다. 진단 라우터는 include_in_schema=False다.
        (output / "team-openapi.json").write_text(
            json.dumps(application.openapi(), ensure_ascii=False, indent=2), encoding="utf-8"
        )
        logging.getLogger("uvicorn").info("diagnostic server uses isolated local database")
        server = uvicorn.Server(
            uvicorn.Config(
                application, host="127.0.0.1", port=port, access_log=False, log_level="warning"
            )
        )

        @application.post("/diagnostic/stop", include_in_schema=False)
        def stop():
            server.should_exit = True
            return {"stopping": True}

        server.run()
    finally:
        if database:
            database.close()
        with psycopg.connect(admin_url, autocommit=True) as conn:
            conn.execute(f'drop database if exists "{name}" with (force)')
        print("diagnostic_database_cleaned=true", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--database-admin-url",
        default="postgresql://postgres:bogle-local-diagnostic@127.0.0.1:55439/postgres",
    )
    args = parser.parse_args()
    run(args.port, args.database_admin_url)
