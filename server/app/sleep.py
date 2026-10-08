"""친구의 수면 시간 (FR-08).

친구는 한국 시간(Asia/Seoul)으로 정해진 시각에 자고 깬다. 기본은 22:00–06:00이고, 앱의 수면
시간 편집으로 친구마다 바꿀 수 있다 (`friends.bedtime_minute`, `wake_minute`). 판정은 서버 시각
기준이다. 자는 시각과 깨는 시각이 같으면 자지 않는 친구다.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from zoneinfo import ZoneInfo

TIME_ZONE = ZoneInfo("Asia/Seoul")
BEDTIME = time(22, 0)
WAKE_TIME = time(6, 0)
BEDTIME_MINUTE = BEDTIME.hour * 60 + BEDTIME.minute
WAKE_MINUTE = WAKE_TIME.hour * 60 + WAKE_TIME.minute

# 자지 않는 친구의 "다음 전환" (먼 미래)
_NEVER = timedelta(days=365)


@dataclass(frozen=True)
class SleepStatus:
    asleep: bool
    # 다음에 자거나 깨는 시각 (UTC)
    next_change_at: datetime


def sleep_status(
    now: datetime, bedtime: int = BEDTIME_MINUTE, wake: int = WAKE_MINUTE
) -> SleepStatus:
    """`now`는 시간대가 있는 시각이어야 한다. 자는 시각 정각은 잠든 것, 깨는 시각 정각은 깬 것.

    `bedtime`, `wake`는 자정부터의 분(한국 시간). 밤을 넘겨도(22:00–06:00) 되고, 낮잠처럼
    같은 날 안이어도(13:00–14:00) 된다.
    """
    if now.tzinfo is None:
        raise ValueError("now must be timezone-aware")
    if bedtime == wake:
        return SleepStatus(asleep=False, next_change_at=(now + _NEVER).astimezone(UTC))

    local = now.astimezone(TIME_ZONE)
    minute = local.hour * 60 + local.minute + local.second / 60 + local.microsecond / 6e7
    if bedtime > wake:
        asleep = minute >= bedtime or minute < wake
    else:
        asleep = bedtime <= minute < wake

    target = wake if asleep else bedtime
    change = datetime.combine(local.date(), time(target // 60, target % 60), tzinfo=TIME_ZONE)
    if change <= local:
        change = datetime.combine(
            local.date() + timedelta(days=1), time(target // 60, target % 60), tzinfo=TIME_ZONE
        )
    return SleepStatus(asleep=asleep, next_change_at=change.astimezone(UTC))
