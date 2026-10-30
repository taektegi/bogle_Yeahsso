"""앱의 개별 수면 일정. 서버 시각을 앱의 UTC 오프셋으로 변환해 판정한다."""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
from typing import Annotated

from fastapi import Header

ClientUtcOffset = Annotated[int, Header(alias="X-Bogle-Utc-Offset-Minutes", ge=-840, le=840)]


@dataclass(frozen=True)
class SleepStatus:
    asleep: bool
    # 다음에 자거나 깨는 시각 (UTC)
    next_change_at: datetime | None


def sleep_status(
    now: datetime, bedtime: int = 21 * 60, wake_time: int = 7 * 60, utc_offset: int = 540
) -> SleepStatus:
    """분 단위 일정, 시작 포함/끝 제외. 같은 시각이면 앱과 같이 항상 깨어 있다."""
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")

    if not (0 <= bedtime < 1440 and 0 <= wake_time < 1440 and -840 <= utc_offset <= 840):
        raise ValueError("invalid sleep schedule or UTC offset")
    if bedtime == wake_time:
        return SleepStatus(False, None)
    local = now.astimezone(timezone(timedelta(minutes=utc_offset)))
    minute = local.hour * 60 + local.minute
    asleep = (
        bedtime <= minute < wake_time
        if bedtime < wake_time
        else minute >= bedtime or minute < wake_time
    )
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    next_change = min(
        candidate
        for day in (0, 1)
        for boundary in (bedtime, wake_time)
        if (candidate := midnight + timedelta(days=day, minutes=boundary)) > local
    )
    return SleepStatus(asleep, next_change.astimezone(UTC))
