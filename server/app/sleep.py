"""친구의 수면 시간 (FR-08, D-15).

모든 친구가 한국 시간(Asia/Seoul) 22:00–06:00에 잔다. 판정은 서버 시각 기준이다.
수동 재우기·수면 일정 편집은 없으므로 시각만으로 결정된다.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

TIME_ZONE = ZoneInfo("Asia/Seoul")
BEDTIME = time(22, 0)
WAKE_TIME = time(6, 0)


@dataclass(frozen=True)
class SleepStatus:
    asleep: bool
    # 다음에 자거나 깨는 시각 (UTC)
    next_change_at: datetime


def sleep_status(now: datetime) -> SleepStatus:
    """`now`는 시간대가 있는 시각이어야 한다. 22:00은 잠든 것, 06:00은 깨어난 것으로 본다."""
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")

    local = now.astimezone(TIME_ZONE)
    asleep = local.time() >= BEDTIME or local.time() < WAKE_TIME

    if not asleep:
        change = datetime.combine(local.date(), BEDTIME, tzinfo=TIME_ZONE)
    elif local.time() >= BEDTIME:
        change = datetime.combine(local.date() + timedelta(days=1), WAKE_TIME, tzinfo=TIME_ZONE)
    else:
        change = datetime.combine(local.date(), WAKE_TIME, tzinfo=TIME_ZONE)
    return SleepStatus(asleep=asleep, next_change_at=change.astimezone(UTC))
