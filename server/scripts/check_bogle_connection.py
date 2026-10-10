"""보글 연결 상태만 확인한다. 비밀값·연결 문자열·외부 오류 본문을 출력하지 않는다."""

import json

import httpx2
import psycopg

from app.config import get_settings

PROJECT_URL = "https://nylnbctmhdfxswsgxmid.supabase.co"


def main():
    result = {}
    try:
        settings = get_settings()
        result["targetBogle"] = settings.supabase_url.rstrip("/") == PROJECT_URL
        result["openrouterConfigured"] = bool(
            settings.openrouter_api_key and settings.openrouter_api_key.get_secret_value()
        )
        if not result["targetBogle"] or settings.database_url is None:
            print(json.dumps(result))
            return 1
        with psycopg.connect(settings.database_url.get_secret_value(), connect_timeout=5) as conn:
            # DB가 지정한 프로젝트에 연결되었는지는 Storage의 서버 키와 함께 확인한다.
            rows = conn.execute(
                "select version,name from supabase_migrations.schema_migrations order by version"
            ).fetchall()
            result["migrationHistory"] = [{"version": v, "name": n} for v, n in rows]
            result["databaseConnected"] = True
            bucket = conn.execute(
                "select public from storage.buckets where id='bogle-media'"
            ).fetchone()
            result["privateBucket"] = bucket is not None and bucket[0] is False
        if settings.supabase_service_role_key:
            key = settings.supabase_service_role_key.get_secret_value()
            response = httpx2.get(
                PROJECT_URL + "/storage/v1/bucket/bogle-media",
                headers={"Authorization": "Bearer " + key, "apikey": key},
                timeout=5,
            )
            result["storageConnected"] = response.status_code == 200
        print(json.dumps(result))
        return 0
    except Exception:
        result["connectionCheckSucceeded"] = False
        print(json.dumps(result))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
