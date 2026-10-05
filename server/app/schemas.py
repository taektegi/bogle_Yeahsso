from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class CamelModel(BaseModel):
    """모든 요청·응답 모델의 기반. JSON 필드는 camelCase, 코드는 snake_case로 쓴다 (NFR-10)."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)
