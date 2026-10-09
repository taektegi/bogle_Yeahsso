"""시연용 임시 계정으로 실제 Auth·Storage·AI·친구 저장을 검증하고 테스트 데이터를 정리한다.

server/에서 `python -m scripts.verify_character_creation`로 명시적으로 실행한다.
유료 이미지 생성은 PNG와 JPEG 입력에 각각 한 번, 최대 두 번이다. 자동 재시도하지 않는다.
비밀값·토큰·서명 URL·외부 응답 본문은 출력하거나 파일에 저장하지 않는다.
"""

import argparse
import io
import json
import secrets
import time
from pathlib import Path
from uuid import UUID, uuid4

import httpx2
import psycopg
from fastapi.testclient import TestClient
from PIL import Image, ImageOps

from app.config import get_settings
from app.friend_settings import INTRODUCTIONS
from app.images import character_image
from app.main import create_app
from app.storage import get_storage
from scripts.check_bogle_connection import PROJECT_URL


class VerificationFailed(Exception):
    def __init__(self, stage):
        self.stage = stage


def require(condition, stage):
    if not condition:
        raise VerificationFailed(stage)


def main(source_types=("drawing", "photo")):
    results = {"cases": [], "testDataCleaned": False}
    user_id = None
    settings = None
    admin = None
    try:
        settings = get_settings()
        require(settings.supabase_url.rstrip("/") == PROJECT_URL, "target")
        require(
            settings.openrouter_api_key and settings.openrouter_api_key.get_secret_value(), "ai_key"
        )
        require(settings.database_url and settings.supabase_service_role_key, "server_settings")
        sample_dir = Path(__file__).resolve().parents[3] / "AI_model" / "drawing"
        samples = sorted(sample_dir.glob("*.jpg"))
        require(len(samples) >= 2, "samples")
        key = settings.supabase_service_role_key.get_secret_value()
        admin = httpx2.Client(headers={"Authorization": "Bearer " + key, "apikey": key}, timeout=15)
        email = f"bogle-creation-test-{uuid4().hex}@example.com"
        password = secrets.token_urlsafe(32)
        response = admin.post(
            PROJECT_URL + "/auth/v1/admin/users",
            json={"email": email, "password": password, "email_confirm": True},
        )
        require(response.status_code in (200, 201), "create_test_user")
        user_id = UUID(response.json()["id"])
        response = admin.post(
            PROJECT_URL + "/auth/v1/token?grant_type=password",
            json={"email": email, "password": password},
        )
        require(response.status_code == 200, "test_login")
        token = response.json()["access_token"]
        headers = {"Authorization": "Bearer " + token}
        with TestClient(create_app(), raise_server_exceptions=False) as client:
            require(
                client.get("/v1/personality-types", headers=headers).status_code == 200,
                "token_verification",
            )
            for source_type in source_types:
                index = 0 if source_type == "drawing" else 1
                case = {"sourceType": source_type}
                job = None
                try:
                    # 시연 샘플만 앱이 내보내는 크기로 준비한다. 원본 샘플은 수정하지 않는다.
                    buffer = io.BytesIO()
                    with Image.open(samples[index]) as raw:
                        image = ImageOps.exif_transpose(raw)
                        image.thumbnail((1536, 1536), Image.Resampling.LANCZOS)
                        image.convert("RGB").save(
                            buffer, "PNG" if source_type == "drawing" else "JPEG"
                        )
                    if source_type == "drawing":
                        data, mime, filename = buffer.getvalue(), "image/png", "drawing.png"
                    else:
                        data, mime, filename = buffer.getvalue(), "image/jpeg", "photo.jpg"
                    started = time.monotonic()
                    response = client.post(
                        "/v1/assets", headers=headers, files={"file": (filename, data, mime)}
                    )
                    require(response.status_code == 201, "upload")
                    source_id = response.json()["assetId"]
                    generation_body = {"sourceAssetId": source_id, "sourceType": source_type}
                    generation_headers = {**headers, "Idempotency-Key": str(uuid4())}
                    response = client.post(
                        "/v1/generations", headers=generation_headers, json=generation_body
                    )
                    require(response.status_code == 202, "enqueue")
                    job_id = response.json()["jobId"]
                    repeat = client.post(
                        "/v1/generations", headers=generation_headers, json=generation_body
                    )
                    require(
                        repeat.status_code == 200 and repeat.json()["jobId"] == job_id, "job_replay"
                    )
                    deadline = time.monotonic() + 310
                    while time.monotonic() < deadline:
                        response = client.get(f"/v1/generations/{job_id}", headers=headers)
                        require(response.status_code == 200, "poll")
                        job = response.json()
                        if job["status"] in ("succeeded", "failed", "cancelled"):
                            break
                        time.sleep(2)
                    require(job["status"] == "succeeded", "generation")
                    require(job["sourceAssetId"] == source_id, "source_mapping")
                    # 앱이 사용하는 만료 URL도 실제로 열리는지 확인한다. URL은 출력하지 않는다.
                    art_response = httpx2.get(job["art"]["url"], timeout=10)
                    require(art_response.status_code == 200, "signed_art_read")
                    art = character_image(art_response.content)
                    require(
                        (art.width, art.height) == (job["art"]["width"], job["art"]["height"]),
                        "dimensions",
                    )
                    require(art.accent_argb == job["accentArgb"], "accent")
                    thumb = httpx2.get(job["thumbnail"]["url"], timeout=10)
                    require(thumb.status_code == 200, "signed_thumbnail_read")
                    with Image.open(io.BytesIO(thumb.content)) as image:
                        require(image.format == "PNG" and image.size == (256, 256), "thumbnail")
                    body = {
                        "generationJobId": job_id,
                        "name": "테스트 친구",
                        "personalityType": "imaginative",
                        "favoriteThings": ["그림", "산책"],
                        "speechStyle": "반말",
                    }
                    save_headers = {**headers, "Idempotency-Key": str(uuid4())}
                    response = client.post("/v1/characters", headers=save_headers, json=body)
                    require(response.status_code == 201, "save_friend")
                    friend = response.json()
                    require(friend["introduction"] in INTRODUCTIONS, "introduction")
                    repeat = client.post("/v1/characters", headers=save_headers, json=body)
                    require(
                        repeat.status_code == 200
                        and repeat.json()["id"] == friend["id"]
                        and repeat.json()["introduction"] == friend["introduction"],
                        "friend_replay",
                    )
                    require(
                        client.get(f"/v1/characters/{friend['id']}", headers=headers).status_code
                        == 200,
                        "friend_query",
                    )
                    require(
                        client.delete(f"/v1/characters/{friend['id']}", headers=headers).status_code
                        == 204,
                        "friend_delete",
                    )
                    require(
                        client.get(f"/v1/generations/{job_id}", headers=headers).status_code == 404,
                        "delete_jobs",
                    )
                    case.update(
                        {
                            "succeeded": True,
                            "width": art.width,
                            "height": art.height,
                            "elapsedSeconds": round(time.monotonic() - started, 2),
                        }
                    )
                except Exception as exc:
                    # AI 본문·키·연결 문자열 대신 직접 정한 단계 이름만 출력한다.
                    stage = exc.stage if isinstance(exc, VerificationFailed) else type(exc).__name__
                    case.update({"succeeded": False, "failedStage": stage})
                    if job is not None and job.get("status") == "failed":
                        case["errorCode"] = job["error"]["code"]
                    results["cases"].append(case)
                    print(json.dumps({"case": case}), flush=True)
                    continue
                results["cases"].append(case)
                print(json.dumps({"case": case}), flush=True)
        results["verified"] = len(results["cases"]) == len(source_types) and all(
            c["succeeded"] for c in results["cases"]
        )
    except Exception as exc:
        results["verified"] = False
        results["errorType"] = type(exc).__name__
    finally:
        if user_id is not None and settings is not None and admin is not None:
            try:
                # 테스트 계정의 파일만 정리한다. 다른 계정의 데이터는 읽거나 변경하지 않는다.
                with psycopg.connect(
                    settings.database_url.get_secret_value(), connect_timeout=5
                ) as conn:
                    rows = conn.execute(
                        "select storage_path from public.assets where user_id=%s", (user_id,)
                    ).fetchall()
                    get_storage(settings).remove([row[0] for row in rows])
                deleted = admin.delete(PROJECT_URL + f"/auth/v1/admin/users/{user_id}")
                results["testDataCleaned"] = deleted.status_code == 200
            except Exception:
                results["testDataCleaned"] = False
        if admin is not None:
            admin.close()
        print(json.dumps(results), flush=True)
    return 0 if results.get("verified") and results["testDataCleaned"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-type", choices=("drawing", "photo", "all"), default="all")
    args = parser.parse_args()
    types = ("drawing", "photo") if args.source_type == "all" else (args.source_type,)
    raise SystemExit(main(types))
