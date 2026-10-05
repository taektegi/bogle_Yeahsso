"""현재 시각. 테스트에서 시각을 고정할 수 있도록 의존성으로 분리한다."""

from datetime import UTC, datetime
from typing import Annotated

from fastapi import Depends


def get_now() -> datetime:
    return datetime.now(UTC)


NowDep = Annotated[datetime, Depends(get_now)]
