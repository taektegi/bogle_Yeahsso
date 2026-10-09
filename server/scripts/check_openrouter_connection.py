"""유료 생성 없이 AI 인증·모델 경로만 점검한다. 키나 응답 본문은 출력하지 않는다."""

import asyncio
import json

import httpx2

from app.config import get_settings
from app.image_provider import error_category
from app.repositories.creation import MODEL


async def async_authentication(key):
    try:
        async with httpx2.AsyncClient(timeout=10) as client:
            response = await client.get(
                "https://openrouter.ai/api/v1/auth/key", headers={"Authorization": "Bearer " + key}
            )
            return {"asyncAuthenticationStatus": response.status_code}
    except Exception as exc:
        return {"asyncAuthenticationErrorType": type(exc).__name__}


def main():
    result = {}
    try:
        key = get_settings().openrouter_api_key
        if key is None:
            result["configured"] = False
        else:
            result["configured"] = True
            response = httpx2.get(
                "https://openrouter.ai/api/v1/auth/key",
                headers={"Authorization": "Bearer " + key.get_secret_value()},
                timeout=10,
            )
            result["authenticationStatus"] = response.status_code
            result["authenticated"] = response.status_code == 200
            result.update(asyncio.run(async_authentication(key.get_secret_value())))
            if response.status_code == 200:
                key_data = response.json().get("data", {})
                remaining = key_data.get("limit_remaining")
                result["keyQuotaAvailable"] = remaining is None or remaining > 0
            response = httpx2.get(
                "https://openrouter.ai/api/v1/credits",
                headers={"Authorization": "Bearer " + key.get_secret_value()},
                timeout=10,
            )
            result["creditsCheckStatus"] = response.status_code
            if response.status_code == 200:
                data = response.json().get("data", {})
                result["accountCreditsAvailable"] = data.get("total_credits", 0) > data.get(
                    "total_usage", 0
                )
            response = httpx2.get(
                "https://openrouter.ai/api/v1/images/models/" + MODEL + "/endpoints", timeout=10
            )
            result["modelEndpointStatus"] = response.status_code
            # n=0은 API 허용 범위(1~10) 밖이라 이미지 생성·과금 없이 요청 경로만 검사한다.
            response = httpx2.post(
                "https://openrouter.ai/api/v1/images",
                headers={"Authorization": "Bearer " + key.get_secret_value()},
                json={"model": MODEL, "prompt": "", "n": 0},
                timeout=10,
            )
            result["invalidRequestStatus"] = response.status_code
            error = response.json().get("error", {})
            if isinstance(error, dict):
                result["invalidRequestCategory"] = error_category(str(error.get("message", "")))
        print(json.dumps(result))
        return 0 if result.get("authenticated") else 1
    except Exception as exc:
        print(json.dumps({"checkSucceeded": False, "errorType": type(exc).__name__}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
