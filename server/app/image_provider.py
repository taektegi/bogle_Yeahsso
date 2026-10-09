"""OpenRouter 이미지 API. 1단계, OpenAI 제공자 고정, 자동 재시도 없음."""

import base64
import binascii
import logging

import httpx2

from app.config import Settings
from app.images import MAX_RESULT_BYTES
from app.repositories.creation import MODEL

logger = logging.getLogger(__name__)


def error_category(message: str) -> str:
    """외부 오류 본문 대신 미리 정한 분류 이름만 진단에 사용한다."""
    message = message.lower()
    if any(value in message for value in ("data policy", "data collection", "privacy")):
        return "data_policy"
    if any(value in message for value in ("no endpoints", "model not found", "model unavailable")):
        return "model_unavailable"
    if any(value in message for value in ("image_url", "input_reference", "reference image")):
        return "invalid_reference"
    if any(value in message for value in ("credits", "payment", "quota", "limit exceeded")):
        return "account_limit"
    if any(value in message for value in ("route", "not found")):
        return "route_unavailable"
    return "other"


PROMPT = """Create exactly ONE character for Bogle, a gentle Korean children's picture-book friend app, from the attached reference drawing/photo. Identify the main central drawing; ignore other partial drawings, ruled notebook lines, paper, hands, desk, shadows and screenshot toolbars. If connected shapes form one invented creature, preserve them together. This is reinterpretation, not a photograph or cleaned scan.
Preserve the original silhouette, proportions, number/placement of eyes, expression, limbs, ears, wings and distinctive decorations. Do not turn every creature into a standard teddy bear or human. Keep original colored marks and decorations. For uncolored pencil-only areas, choose ONE flat warm pastel base color (peach, pale yellow or lavender) without inventing accessories, patterns, stars, spots, patches, hats or extra limbs. Preserve unusual anatomy and asymmetry; gently soften frightening expressions without removing identifying traits.
Art direction: clean FLAT 2D vector-like storybook mascot with SOLID color fills, simple playful rounded shapes, clean smooth edges, minimal detail, almost no outlines. Warm, approachable and childlike; fits a cream-and-lavender app. NO texture, grain, watercolor, shading, glow, halo, gradients, 3D, plush, glossy toy, anime or photorealism. Body should be solid opaque; only the outside and smooth silhouette edge use alpha.
Composition: entire single figure centered on a square canvas, about 80% of the canvas with safe transparent margins; keep all appendages inside the frame. Use front/three-quarter view appropriate to the original silhouette, do not force a quadruped to stand upright.
Deliver ONE PNG with a truly transparent alpha background. Only the character: no paper, notebook lines, background, scenery, floor, ground shadow, frame, text, logos or watermark. Do not paint a checkerboard or white rectangle to simulate transparency."""  # noqa: E501


class GenerationError(Exception):
    def __init__(self, code: str, message: str, retryable: bool):
        super().__init__(message)
        self.code, self.message, self.retryable = code, message, retryable


class OpenRouterImages:
    def __init__(self, settings: Settings, transport=None):
        self.settings = settings
        self.transport = transport

    async def generate(self, reference: str) -> bytes:
        key = self.settings.openrouter_api_key
        if key is None or not key.get_secret_value():
            raise GenerationError(
                "generation_unavailable", "이미지 생성 서비스 설정이 필요해요.", False
            )
        try:
            async with httpx2.AsyncClient(
                timeout=self.settings.generation_timeout_seconds, transport=self.transport
            ) as client:
                response = await client.post(
                    "https://openrouter.ai/api/v1/images",
                    headers={"Authorization": "Bearer " + key.get_secret_value()},
                    json={
                        "model": MODEL,
                        "prompt": PROMPT,
                        "n": 1,
                        "aspect_ratio": "1:1",
                        "quality": "medium",
                        "background": "transparent",
                        "provider": {"only": ["openai"], "allow_fallbacks": False},
                        "input_references": [
                            {"type": "image_url", "image_url": {"url": reference}}
                        ],
                    },
                )
        except httpx2.TimeoutException:
            raise GenerationError(
                "generation_timeout", "생성 시간이 길어져 중단됐어요.", True
            ) from None
        except httpx2.HTTPError as exc:
            logger.warning("image provider connection failed errorType=%s", type(exc).__name__)
            raise GenerationError(
                "generation_unavailable", "이미지 생성 서비스에 연결하지 못했어요.", True
            ) from None
        if response.status_code != 200:
            logger.warning("image provider rejected request status=%d", response.status_code)
            # 오류 본문은 출력하거나 사용자에게 전달하지 않고 내부 분류에만 사용한다.
            try:
                error = response.json().get("error", {})
                code = str(error.get("code", "")).lower() if isinstance(error, dict) else ""
            except ValueError:
                code = ""
                error = {}
            category = (
                error_category(str(error.get("message", "")))
                if isinstance(error, dict)
                else "other"
            )
            logger.warning("image provider failure category=%s", category)
            if category == "data_policy" or code == "data_policy":
                raise GenerationError(
                    "generation_unavailable", "이미지 생성 서비스 설정이 필요해요.", False
                )
            if any(word in code for word in ("moderation", "policy", "safety", "content_filter")):
                raise GenerationError(
                    "generation_rejected", "이 그림으로는 캐릭터를 만들 수 없어요.", False
                )
            if response.status_code in (400, 422):
                raise GenerationError(
                    "invalid_source_image", "생성에 사용할 그림을 확인해 주세요.", False
                )
            raise GenerationError(
                "generation_unavailable",
                "이미지 생성 서비스를 잠시 사용할 수 없어요.",
                response.status_code == 429 or response.status_code >= 500,
            )
        try:
            items = response.json()["data"]
            if len(items) != 1:
                raise ValueError
            encoded = items[0]["b64_json"]
            if not isinstance(encoded, str) or len(encoded) > MAX_RESULT_BYTES * 4 // 3 + 4:
                raise ValueError
            return base64.b64decode(encoded, validate=True)
        except (ValueError, KeyError, TypeError, binascii.Error):
            raise GenerationError(
                "generation_invalid_result", "캐릭터 이미지 결과를 읽을 수 없어요.", True
            ) from None
