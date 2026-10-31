"""외부 이미지 오류를 원문·키 없이 분류하고 승인된 실호출을 한 번 수행한다."""

import argparse
import asyncio
import json
import logging
from pathlib import Path

import httpx2

from app.config import get_settings
from app.image_provider import GenerationError, OpenRouterImages, error_category
from app.images import character_image, input_reference
from app.repositories.creation import MODEL
from scripts.diagnose_live_services import sample


class ObservedTransport(httpx2.AsyncBaseTransport):
    def __init__(self, evidence):
        self.actual = httpx2.AsyncHTTPTransport()
        self.evidence = evidence

    async def handle_async_request(self, request):
        response = await self.actual.handle_async_request(request)
        self.evidence["httpStatus"] = response.status_code
        if response.status_code != 200:
            await response.aread()
            try:
                error = response.json().get("error", {})
                message = str(error.get("message", "")).lower()
                self.evidence["category"] = error_category(message)
                self.evidence["dataPolicyMentioned"] = "data policy" in message
                self.evidence["privacySettingsMentioned"] = "privacy" in message
                self.evidence["providerAuthenticationMentioned"] = any(
                    word in message for word in ("api key", "unauthorized", "authentication")
                )
            except (ValueError, AttributeError):
                self.evidence["category"] = "unclassified"
        return response

    async def aclose(self):
        await self.actual.aclose()


async def main(generate, output):
    logging.disable(logging.CRITICAL)
    settings = get_settings()
    evidence = {"model": MODEL, "generated": False}
    if not settings.openrouter_api_key:
        evidence["blocked"] = "image_key_not_configured"
    else:
        headers = {"Authorization": "Bearer " + settings.openrouter_api_key.get_secret_value()}
        async with httpx2.AsyncClient(timeout=30) as client:
            response = await client.get("https://openrouter.ai/api/v1/key", headers=headers)
            evidence["keyAuthenticationSucceeded"] = response.status_code == 200
            response = await client.get(
                f"https://openrouter.ai/api/v1/images/models/{MODEL}/endpoints", headers=headers
            )
            evidence["modelDiscoverySucceeded"] = response.status_code == 200
            if response.status_code == 200:
                data = response.json().get("data", response.json())
                endpoints = data.get("endpoints", []) if isinstance(data, dict) else data
                evidence["endpoints"] = [
                    {
                        key: endpoint[key]
                        for key in (
                            "provider_name",
                            "provider",
                            "provider_slug",
                            "name",
                            "supported_parameters",
                            "supports_streaming",
                        )
                        if key in endpoint
                    }
                    for endpoint in endpoints
                    if isinstance(endpoint, dict)
                ]
        if generate:
            transport = ObservedTransport(evidence)
            try:
                data = await OpenRouterImages(settings, transport).generate(
                    input_reference(sample("drawing"))
                )
                image = character_image(data)
                image_path = output.with_suffix(".png")
                image_path.write_bytes(image.art)
                evidence.update(
                    {
                        "generated": True,
                        "width": image.width,
                        "height": image.height,
                        "transparentPngValidated": True,
                        "imageFile": image_path.name,
                    }
                )
            except GenerationError as error:
                evidence.update({"code": error.code, "retryable": error.retryable})
            except Exception as error:
                evidence["errorType"] = type(error).__name__
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(evidence, ensure_ascii=True, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("기존 증거를 덮어쓰지 않는다. 새 출력 경로를 지정해 주세요.")
    asyncio.run(main(args.generate, args.output))
