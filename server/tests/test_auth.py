import base64
import hashlib
import hmac
import json
import time
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from tests.conftest import SUPABASE_URL
from tests.tokens import USER_ID, bearer, claims, hs256_token

ME = "/v1/_probe/me"


def assert_unauthenticated(response) -> None:
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    body = response.json()["error"]
    assert body["code"] == "unauthenticated"
    assert body["retryable"] is False


def test_user_id_comes_from_token_sub(client: TestClient) -> None:
    response = client.get(ME, headers=bearer(hs256_token()))
    assert response.status_code == 200
    assert response.json() == {"userId": USER_ID}


def test_user_id_in_query_or_body_is_ignored(client: TestClient) -> None:
    other = "99999999-9999-4999-8999-999999999999"
    response = client.get(ME, params={"userId": other}, headers=bearer(hs256_token()))
    assert response.json() == {"userId": USER_ID}


def test_missing_token_is_rejected(client: TestClient) -> None:
    assert_unauthenticated(client.get(ME))


def test_non_bearer_scheme_is_rejected(client: TestClient) -> None:
    assert_unauthenticated(client.get(ME, headers={"Authorization": "Basic abc"}))


def test_garbage_token_is_rejected(client: TestClient) -> None:
    assert_unauthenticated(client.get(ME, headers=bearer("not-a-jwt")))


def test_wrong_secret_is_rejected(client: TestClient) -> None:
    token = hs256_token(secret="another-secret-another-secret-0123456789")
    assert_unauthenticated(client.get(ME, headers=bearer(token)))


def test_expired_token_is_rejected(client: TestClient) -> None:
    token = hs256_token(exp=int(time.time()) - 10)
    assert_unauthenticated(client.get(ME, headers=bearer(token)))


def test_token_without_exp_is_rejected(client: TestClient) -> None:
    assert_unauthenticated(client.get(ME, headers=bearer(hs256_token(exp=None))))


def test_wrong_audience_is_rejected(client: TestClient) -> None:
    assert_unauthenticated(client.get(ME, headers=bearer(hs256_token(aud="other"))))


def test_wrong_issuer_is_rejected(client: TestClient) -> None:
    token = hs256_token(iss="https://evil.supabase.co/auth/v1")
    assert_unauthenticated(client.get(ME, headers=bearer(token)))


def test_token_without_sub_is_rejected(client: TestClient) -> None:
    # 익명(anon) 키 토큰처럼 사용자가 없는 토큰
    assert_unauthenticated(client.get(ME, headers=bearer(hs256_token(sub=None))))


def test_non_uuid_sub_is_rejected(client: TestClient) -> None:
    assert_unauthenticated(client.get(ME, headers=bearer(hs256_token(sub="not-a-uuid"))))


def test_alg_none_is_rejected(client: TestClient) -> None:
    token = jwt.encode(claims(), None, algorithm="none")
    assert_unauthenticated(client.get(ME, headers=bearer(token)))


def test_hs256_is_rejected_when_secret_is_not_configured(app, client: TestClient) -> None:
    app.dependency_overrides[get_settings] = lambda: Settings(
        _env_file=None, supabase_url=SUPABASE_URL
    )
    assert_unauthenticated(client.get(ME, headers=bearer(hs256_token())))


def test_issuer_is_not_checked_when_supabase_url_is_unset(
    app, client: TestClient, settings
) -> None:
    app.dependency_overrides[get_settings] = lambda: Settings(
        _env_file=None, supabase_jwt_secret=settings.supabase_jwt_secret
    )
    token = hs256_token(iss="https://anything.example/auth/v1")
    assert client.get(ME, headers=bearer(token)).status_code == 200


class FakeJwksClient:
    def __init__(self, public_key) -> None:
        self.public_key = public_key

    def get_signing_key_from_jwt(self, token: str) -> SimpleNamespace:
        return SimpleNamespace(key=self.public_key)


@pytest.fixture
def es256(monkeypatch: pytest.MonkeyPatch):
    """비대칭 키 프로젝트: JWKS에서 공개 키를 받는 것을 가짜 클라이언트로 대신한다."""
    private_key = ec.generate_private_key(ec.SECP256R1())
    requested: list[str] = []

    def fake_client(jwks_url: str) -> FakeJwksClient:
        requested.append(jwks_url)
        return FakeJwksClient(private_key.public_key())

    monkeypatch.setattr("app.auth._get_jwks_client", fake_client)
    return SimpleNamespace(private_key=private_key, requested=requested)


def es256_token(private_key, **overrides) -> str:
    return jwt.encode(claims(**overrides), private_key, algorithm="ES256", headers={"kid": "k1"})


def test_es256_token_is_verified_with_jwks(client: TestClient, es256) -> None:
    response = client.get(ME, headers=bearer(es256_token(es256.private_key)))
    assert response.status_code == 200
    assert response.json() == {"userId": USER_ID}
    assert es256.requested == [f"{SUPABASE_URL}/auth/v1/.well-known/jwks.json"]


def test_es256_token_signed_by_another_key_is_rejected(client: TestClient, es256) -> None:
    attacker_key = ec.generate_private_key(ec.SECP256R1())
    assert_unauthenticated(client.get(ME, headers=bearer(es256_token(attacker_key))))


def test_es256_is_rejected_when_supabase_url_is_unset(
    app, client: TestClient, es256, settings
) -> None:
    app.dependency_overrides[get_settings] = lambda: Settings(
        _env_file=None, supabase_jwt_secret=settings.supabase_jwt_secret
    )
    assert_unauthenticated(client.get(ME, headers=bearer(es256_token(es256.private_key))))
    assert es256.requested == []


def test_hs256_token_signed_with_public_key_text_is_rejected(client: TestClient, es256) -> None:
    # 알고리즘 혼동 공격: 공개 키를 HMAC 비밀처럼 써서 서명한 HS256 토큰
    public_pem = es256.private_key.public_key().public_bytes(
        Encoding.PEM, PublicFormat.SubjectPublicKeyInfo
    )

    def b64(data: bytes) -> bytes:
        return base64.urlsafe_b64encode(data).rstrip(b"=")

    # PyJWT는 PEM 키로 HS256 서명하는 것을 거부하므로, 공격자처럼 직접 HMAC을 계산한다.
    signing_input = (
        b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
        + b"."
        + b64(json.dumps(claims()).encode())
    )
    signature = hmac.new(public_pem, signing_input, hashlib.sha256).digest()
    token = (signing_input + b"." + b64(signature)).decode()
    assert_unauthenticated(client.get(ME, headers=bearer(token)))
