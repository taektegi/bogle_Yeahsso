import time
from typing import Any

import jwt

from tests.conftest import JWT_SECRET, SUPABASE_URL

USER_ID = "11111111-2222-4333-8444-555555555555"


def claims(**overrides: Any) -> dict[str, Any]:
    now = int(time.time())
    base: dict[str, Any] = {
        "sub": USER_ID,
        "aud": "authenticated",
        "iss": f"{SUPABASE_URL}/auth/v1",
        "role": "authenticated",
        "iat": now,
        "exp": now + 3600,
    }
    base.update(overrides)
    # None으로 덮어쓴 값은 클레임 자체를 뺀다.
    return {k: v for k, v in base.items() if v is not None}


def hs256_token(secret: str = JWT_SECRET, **overrides: Any) -> str:
    return jwt.encode(claims(**overrides), secret, algorithm="HS256")


def bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}
