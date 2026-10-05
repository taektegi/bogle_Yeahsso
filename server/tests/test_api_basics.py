import logging

from fastapi.testclient import TestClient

REQUEST_ID = "X-Request-Id"


def error_of(response) -> dict:
    return response.json()["error"]


def test_health_is_public_and_versioned(client: TestClient) -> None:
    response = client.get("/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_unversioned_path_is_not_found(client: TestClient) -> None:
    assert client.get("/health").status_code == 404


def test_response_gets_a_generated_request_id(client: TestClient) -> None:
    response = client.get("/v1/health")
    assert len(response.headers[REQUEST_ID]) == 32


def test_valid_incoming_request_id_is_kept(client: TestClient) -> None:
    response = client.get("/v1/health", headers={REQUEST_ID: "app-request-0001"})
    assert response.headers[REQUEST_ID] == "app-request-0001"


def test_invalid_incoming_request_id_is_replaced(client: TestClient) -> None:
    response = client.get("/v1/health", headers={REQUEST_ID: "bad id\twith spaces!"})
    assert response.headers[REQUEST_ID] != "bad id\twith spaces!"
    assert len(response.headers[REQUEST_ID]) == 32


def test_not_found_uses_common_error_format(client: TestClient) -> None:
    response = client.get("/v1/nope", headers={REQUEST_ID: "req-not-found-1"})
    assert response.status_code == 404
    assert response.json() == {
        "error": {
            "code": "not_found",
            "message": "찾을 수 없어요.",
            "retryable": False,
            "fieldErrors": {},
            "requestId": "req-not-found-1",
        }
    }
    assert response.headers[REQUEST_ID] == "req-not-found-1"


def test_method_not_allowed_uses_common_error_format(client: TestClient) -> None:
    response = client.post("/v1/health")
    assert response.status_code == 405
    assert error_of(response)["code"] == "method_not_allowed"


def test_api_error_uses_its_own_code_and_message(client: TestClient) -> None:
    response = client.get("/v1/_probe/api-error")
    assert response.status_code == 404
    assert error_of(response)["code"] == "friend_not_found"
    assert error_of(response)["message"] == "친구를 찾을 수 없어요."
    assert error_of(response)["requestId"] == response.headers[REQUEST_ID]


def test_retryable_flag_is_passed_through(client: TestClient) -> None:
    response = client.get("/v1/_probe/retryable")
    assert response.status_code == 503
    assert error_of(response)["retryable"] is True


def test_request_body_uses_camel_case_and_validation_errors_name_the_field(
    client: TestClient,
) -> None:
    ok = client.post("/v1/_probe/echo", json={"friendName": "뭉글이", "favoriteThings": ["사과"]})
    assert ok.status_code == 200
    assert ok.json() == {"friendName": "뭉글이", "favoriteThings": ["사과"]}

    bad = client.post("/v1/_probe/echo", json={"friendName": "a", "favoriteThings": []})
    assert bad.status_code == 422
    assert error_of(bad)["code"] == "validation_error"
    assert error_of(bad)["fieldErrors"] == {
        "friendName": "string_too_short",
        "favoriteThings": "too_short",
    }


def test_missing_body_field_is_reported(client: TestClient) -> None:
    response = client.post("/v1/_probe/echo", json={"favoriteThings": ["사과"]})
    assert response.status_code == 422
    assert error_of(response)["fieldErrors"] == {"friendName": "missing"}


def test_malformed_json_is_a_validation_error(client: TestClient) -> None:
    response = client.post(
        "/v1/_probe/echo", content=b"{not json", headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 422
    assert error_of(response)["code"] == "validation_error"


def test_unexpected_error_hides_details_but_keeps_request_id(client: TestClient, caplog) -> None:
    with caplog.at_level(logging.ERROR, logger="app"):
        response = client.get("/v1/_probe/boom", headers={REQUEST_ID: "req-boom-0001"})
    assert response.status_code == 500
    body = error_of(response)
    assert body["code"] == "internal_error"
    assert body["requestId"] == "req-boom-0001"
    assert response.headers[REQUEST_ID] == "req-boom-0001"
    assert "sk-should-never-leak" not in response.text
    assert "RuntimeError" not in response.text
    # 원인은 로그에만 남는다.
    assert any(r.exc_info for r in caplog.records)


def test_access_log_has_method_path_status_but_no_query(client: TestClient, caplog) -> None:
    with caplog.at_level(logging.INFO, logger="app.access"):
        client.get("/v1/health", params={"secret": "do-not-log"})
    messages = [r.getMessage() for r in caplog.records if r.name == "app.access"]
    assert any(m.startswith("GET /v1/health -> 200") for m in messages)
    assert not any("do-not-log" in m for m in messages)


def test_openapi_documents_v1_health(client: TestClient) -> None:
    schema = client.get("/openapi.json").json()
    assert "/v1/health" in schema["paths"]
    assert client.get("/docs").status_code == 200
