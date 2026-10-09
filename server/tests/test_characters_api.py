"""보관함 API의 응답 모양과 오류 처리. DB 없이 가짜 repository로 확인한다.

소유자로 거르는 SQL 자체는 test_characters_db.py에서 실제 DB로 확인한다.
"""

from datetime import UTC, datetime
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.assets import AssetRow
from app.clock import get_now
from app.config import Settings, get_settings
from app.face_analysis import FaceMap
from app.repositories.characters import CharacterRecord, get_character_repository
from app.storage import get_storage
from tests.conftest import JWT_SECRET, SUPABASE_URL
from tests.db_support import FakeStorage
from tests.tokens import USER_ID, bearer, hs256_token


def asset(user: str, kind: str) -> AssetRow:
    asset_id = uuid4()
    ext = "jpg" if kind == "source" else "png"
    return AssetRow(
        id=asset_id,
        storage_path=f"{user}/{asset_id}.{ext}",
        content_type="image/jpeg" if kind == "source" else "image/png",
        width=640,
        height=480,
    )


def record(name: str = "구름이", personality_type: str = "calm", with_source: bool = True):
    return CharacterRecord(
        id=uuid4(),
        name=name,
        personality_type=personality_type,
        favorite_things=["구름", "사과"],
        speech_style="해요체",
        introduction="하늘 위에서 놀다 왔어!",
        accent_argb=4289974783,
        created_at=datetime(2026, 10, 5, 5, 1, tzinfo=UTC),
        face=FaceMap.model_validate(
            {
                "version": 1,
                "size": [640, 480],
                "facing": "front",
                "head": [160, 60, 320, 300],
                "eyes": [[250, 160, 24], [390, 160, 24]],
                "mouth": [320, 260, 90, 36],
                "cheeks": [[225, 225, 28], [415, 225, 28]],
            },
            context={"expected_size": (640, 480)},
        ),
        source=asset(USER_ID, "source") if with_source else None,
        art=asset(USER_ID, "art"),
        thumbnail=asset(USER_ID, "thumbnail"),
    )


class FakeRepository:
    def __init__(self, records: list[CharacterRecord]) -> None:
        self.records = records

    def list_for_user(self, user_id: UUID) -> list[CharacterRecord]:
        return self.records

    def get_for_user(self, user_id: UUID, character_id: UUID) -> CharacterRecord | None:
        return next((r for r in self.records if r.id == character_id), None)

    def exists_for_user(self, user_id: UUID, character_id: UUID) -> bool:
        return self.get_for_user(user_id, character_id) is not None


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


def use(app, records: list[CharacterRecord], storage: FakeStorage) -> None:
    app.dependency_overrides[get_character_repository] = lambda: FakeRepository(records)
    app.dependency_overrides[get_storage] = lambda: storage


def test_list_response_shape_is_camel_case(app, client: TestClient, storage) -> None:
    item = record()
    use(app, [item], storage)

    response = client.get("/v1/characters", headers=bearer(hs256_token()))

    assert response.status_code == 200
    body = response.json()
    assert body["nextCursor"] is None
    [character] = body["items"]
    assert set(character) == {
        "id", "name", "personalityType", "personalityLabel", "introduction", "favoriteThings",
        "speechStyle", "source", "art", "thumbnail", "accentArgb", "face", "createdAt",
    }  # fmt: skip
    assert character["id"] == str(item.id)
    assert character["name"] == "구름이"
    assert character["personalityType"] == "calm"
    assert character["personalityLabel"] == "느긋하고 차분해요"
    assert character["favoriteThings"] == ["구름", "사과"]
    assert character["speechStyle"] == "해요체"
    assert character["accentArgb"] == 4289974783
    assert character["face"]["version"] == 1
    assert character["face"]["size"] == [640, 480]
    assert character["createdAt"] == "2026-10-05T05:01:00Z"


def test_images_are_signed_url_objects(app, client: TestClient, storage) -> None:
    item = record()
    use(app, [item], storage)

    [character] = client.get("/v1/characters", headers=bearer(hs256_token())).json()["items"]

    assert character["art"] == {
        "assetId": str(item.art.id),
        "url": f"https://storage.test/signed/{item.art.storage_path}?token=t",
        "expiresAt": "2026-10-05T06:00:00Z",
        "contentType": "image/png",
        "width": 640,
        "height": 480,
    }
    assert character["source"]["contentType"] == "image/jpeg"
    assert character["thumbnail"]["assetId"] == str(item.thumbnail.id)


def test_one_signing_request_covers_the_whole_list(app, client: TestClient, storage) -> None:
    records = [record("하나"), record("둘", with_source=False)]
    use(app, records, storage)

    client.get("/v1/characters", headers=bearer(hs256_token()))

    assert len(storage.calls) == 1
    assert len(storage.calls[0]) == 5  # 3 + 2(원본 없는 친구)


def test_missing_source_is_null(app, client: TestClient, storage) -> None:
    use(app, [record(with_source=False)], storage)

    [character] = client.get("/v1/characters", headers=bearer(hs256_token())).json()["items"]

    assert character["source"] is None
    assert character["art"] is not None


def test_character_with_a_lost_art_file_is_left_out_of_the_list(app, client, storage) -> None:
    broken, fine = record("깨진친구"), record("멀쩡한친구")
    storage.missing = {broken.art.storage_path}
    use(app, [broken, fine], storage)

    response = client.get("/v1/characters", headers=bearer(hs256_token()))

    assert response.status_code == 200
    assert [c["name"] for c in response.json()["items"]] == ["멀쩡한친구"]


def test_lost_source_file_only_makes_source_null(app, client, storage) -> None:
    item = record()
    storage.missing = {item.source.storage_path}
    use(app, [item], storage)

    [character] = client.get("/v1/characters", headers=bearer(hs256_token())).json()["items"]

    assert character["source"] is None
    assert character["art"]["assetId"] == str(item.art.id)


def test_detail_of_a_character_with_a_lost_thumbnail_is_404(app, client, storage) -> None:
    item = record()
    storage.missing = {item.thumbnail.storage_path}
    use(app, [item], storage)

    response = client.get(f"/v1/characters/{item.id}", headers=bearer(hs256_token()))

    assert response.status_code == 404


def test_empty_list(app, client: TestClient, storage) -> None:
    use(app, [], storage)

    response = client.get("/v1/characters", headers=bearer(hs256_token()))

    assert response.status_code == 200
    assert response.json() == {"items": [], "nextCursor": None}


def test_unknown_personality_type_falls_back_to_the_code(app, client: TestClient, storage) -> None:
    use(app, [record(personality_type="retired_type")], storage)

    [character] = client.get("/v1/characters", headers=bearer(hs256_token())).json()["items"]

    assert character["personalityType"] == "retired_type"
    assert character["personalityLabel"] == "retired_type"


def test_detail_returns_the_character(app, client: TestClient, storage) -> None:
    item = record()
    use(app, [item], storage)

    response = client.get(f"/v1/characters/{item.id}", headers=bearer(hs256_token()))

    assert response.status_code == 200
    assert response.json()["id"] == str(item.id)


def test_detail_of_unknown_character_is_404(app, client: TestClient, storage) -> None:
    use(app, [], storage)

    response = client.get(f"/v1/characters/{uuid4()}", headers=bearer(hs256_token()))

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_malformed_character_id_is_a_validation_error(app, client: TestClient, storage) -> None:
    use(app, [], storage)

    response = client.get("/v1/characters/not-a-uuid", headers=bearer(hs256_token()))

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


@pytest.mark.parametrize("path", ["/v1/characters", f"/v1/characters/{uuid4()}"])
def test_login_is_required(client: TestClient, path: str) -> None:
    response = client.get(path)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "unauthenticated"


def test_storage_failure_is_a_retryable_503(app, client: TestClient) -> None:
    use(app, [record()], FakeStorage(fail=True))

    response = client.get("/v1/characters", headers=bearer(hs256_token()))

    assert response.status_code == 503
    error = response.json()["error"]
    assert error["code"] == "service_unavailable"
    assert error["retryable"] is True
    assert "storage is down" not in response.text


def test_missing_database_configuration_is_a_503(client: TestClient) -> None:
    # DATABASE_URL이 없어서 서버에 DB 풀이 없는 상태
    response = client.get("/v1/characters", headers=bearer(hs256_token()))

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "service_unavailable"


def test_missing_storage_configuration_is_a_503(app, client: TestClient, storage) -> None:
    app.dependency_overrides[get_character_repository] = lambda: FakeRepository([record()])
    app.dependency_overrides[get_settings] = lambda: Settings(
        _env_file=None, supabase_url=SUPABASE_URL, supabase_jwt_secret=JWT_SECRET
    )  # SUPABASE_SERVICE_ROLE_KEY 없음

    response = client.get("/v1/characters", headers=bearer(hs256_token()))

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "service_unavailable"


def test_openapi_documents_the_character_endpoints(client: TestClient) -> None:
    paths = client.get("/openapi.json").json()["paths"]
    assert "get" in paths["/v1/characters"]
    assert "get" in paths["/v1/characters/{character_id}"]


def freeze_time(app, iso: str) -> None:
    app.dependency_overrides[get_now] = lambda: datetime.fromisoformat(iso)


def test_status_while_asleep(app, client: TestClient, storage) -> None:
    item = record()
    use(app, [item], storage)
    freeze_time(app, "2026-10-05T13:00:00+00:00")  # 22:00 KST

    response = client.get(f"/v1/characters/{item.id}/status", headers=bearer(hs256_token()))

    assert response.status_code == 200
    assert response.json() == {
        "asleep": True,
        "nextChangeAt": "2026-10-05T21:00:00Z",  # 다음 날 06:00 KST
        "serverTime": "2026-10-05T13:00:00Z",
    }


def test_status_while_awake(app, client: TestClient, storage) -> None:
    item = record()
    use(app, [item], storage)
    freeze_time(app, "2026-10-05T05:00:00+00:00")  # 14:00 KST

    response = client.get(f"/v1/characters/{item.id}/status", headers=bearer(hs256_token()))

    assert response.json() == {
        "asleep": False,
        "nextChangeAt": "2026-10-05T13:00:00Z",  # 22:00 KST
        "serverTime": "2026-10-05T05:00:00Z",
    }


def test_status_of_unknown_character_is_404(app, client: TestClient, storage) -> None:
    use(app, [], storage)

    response = client.get(f"/v1/characters/{uuid4()}/status", headers=bearer(hs256_token()))

    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_status_requires_login(client: TestClient) -> None:
    assert client.get(f"/v1/characters/{uuid4()}/status").status_code == 401
