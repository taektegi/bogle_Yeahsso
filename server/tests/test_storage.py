import json
from datetime import UTC, datetime, timedelta

import httpx2
import pytest

from app.storage import StorageError, SupabaseStorage

NOW = datetime(2026, 10, 5, 5, 0, tzinfo=UTC)
USER_ID = "11111111-2222-4333-8444-555555555555"


def make_storage(handler) -> SupabaseStorage:
    return SupabaseStorage(
        supabase_url="https://proj.supabase.co/",
        service_role_key="service-role-key",
        bucket="bogle-media",
        ttl_seconds=3600,
        client=httpx2.Client(transport=httpx2.MockTransport(handler)),
        clock=lambda: NOW,
    )


def signed_items(paths: list[str]) -> list[dict]:
    return [
        {"error": None, "path": p, "signedURL": f"/object/sign/bogle-media/{p}?token=abc"}
        for p in paths
    ]


def test_signs_all_paths_in_one_request() -> None:
    requests: list[httpx2.Request] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        requests.append(request)
        paths = json.loads(request.content)["paths"]
        return httpx2.Response(200, json=signed_items(paths))

    result = make_storage(handler).sign([f"{USER_ID}/a.png", f"{USER_ID}/b.png"])

    assert len(requests) == 1
    request = requests[0]
    assert request.method == "POST"
    assert str(request.url) == "https://proj.supabase.co/storage/v1/object/sign/bogle-media"
    assert request.headers["authorization"] == "Bearer service-role-key"
    assert request.headers["apikey"] == "service-role-key"
    assert json.loads(request.content) == {
        "expiresIn": 3600,
        "paths": [f"{USER_ID}/a.png", f"{USER_ID}/b.png"],
    }
    signed = result[f"{USER_ID}/a.png"]
    assert signed.url == (
        f"https://proj.supabase.co/storage/v1/object/sign/bogle-media/{USER_ID}/a.png?token=abc"
    )
    assert signed.expires_at == NOW + timedelta(hours=1)


def test_duplicate_paths_are_requested_once() -> None:
    sent: list[list[str]] = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        paths = json.loads(request.content)["paths"]
        sent.append(paths)
        return httpx2.Response(200, json=signed_items(paths))

    result = make_storage(handler).sign(["x/a.png", "x/b.png", "x/a.png"])

    assert sent == [["x/a.png", "x/b.png"]]
    assert set(result) == {"x/a.png", "x/b.png"}


def test_no_paths_means_no_request() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise AssertionError("storage must not be called")

    assert make_storage(handler).sign([]) == {}


def test_http_error_is_a_storage_error() -> None:
    storage = make_storage(lambda request: httpx2.Response(500, json={"message": "boom"}))
    with pytest.raises(StorageError):
        storage.sign(["x/a.png"])


def test_unauthorized_is_a_storage_error_without_leaking_the_key() -> None:
    storage = make_storage(lambda request: httpx2.Response(401, json={"message": "bad key"}))
    with pytest.raises(StorageError) as excinfo:
        storage.sign(["x/a.png"])
    assert "service-role-key" not in str(excinfo.value)


def test_item_level_error_is_a_storage_error() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(
            200, json=[{"error": "Object not found", "path": "x/a.png", "signedURL": None}]
        )

    with pytest.raises(StorageError):
        make_storage(handler).sign(["x/a.png"])


def test_response_missing_a_path_is_a_storage_error() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(200, json=signed_items(["x/a.png"]))

    with pytest.raises(StorageError):
        make_storage(handler).sign(["x/a.png", "x/b.png"])


def test_network_failure_is_a_storage_error() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ConnectError("connection refused")

    with pytest.raises(StorageError):
        make_storage(handler).sign(["x/a.png"])
