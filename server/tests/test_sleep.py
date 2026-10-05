from datetime import UTC, datetime, timedelta, timezone

import pytest

from app.sleep import sleep_status

KST = timezone(timedelta(hours=9))


def kst(text: str) -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=KST)


@pytest.mark.parametrize(
    ("now", "asleep", "next_change"),
    [
        # 깨어 있는 시간 → 다음 전환은 같은 날 22:00
        ("2026-10-05T06:00:00", False, "2026-10-05T22:00:00"),  # 06:00 정각에 깨어남
        ("2026-10-05T12:00:00", False, "2026-10-05T22:00:00"),
        ("2026-10-05T21:59:59", False, "2026-10-05T22:00:00"),
        # 자는 시간 → 22:00 이후는 다음 날 06:00, 자정 이후는 같은 날 06:00
        ("2026-10-05T22:00:00", True, "2026-10-06T06:00:00"),  # 22:00 정각에 잠듦
        ("2026-10-05T23:30:00", True, "2026-10-06T06:00:00"),
        ("2026-10-06T00:00:00", True, "2026-10-06T06:00:00"),
        ("2026-10-06T05:59:59", True, "2026-10-06T06:00:00"),
    ],
)
def test_sleep_window_boundaries(now: str, asleep: bool, next_change: str) -> None:
    status = sleep_status(kst(now))

    assert status.asleep is asleep
    assert status.next_change_at == kst(next_change)


def test_next_change_is_reported_in_utc() -> None:
    status = sleep_status(kst("2026-10-05T12:00:00"))

    assert status.next_change_at.utcoffset() == timedelta(0)
    assert status.next_change_at.isoformat() == "2026-10-05T13:00:00+00:00"


def test_utc_input_is_converted_to_korean_time() -> None:
    # 2026-10-05T13:00Z == 22:00 KST → 잠듦
    assert sleep_status(datetime(2026, 10, 5, 13, 0, tzinfo=UTC)).asleep is True
    # 2026-10-05T20:59Z == 05:59 KST (다음 날) → 아직 잠
    asleep = sleep_status(datetime(2026, 10, 5, 20, 59, tzinfo=UTC))
    assert asleep.asleep is True
    assert asleep.next_change_at == datetime(2026, 10, 5, 21, 0, tzinfo=UTC)
    # 2026-10-05T21:00Z == 06:00 KST → 깨어남
    assert sleep_status(datetime(2026, 10, 5, 21, 0, tzinfo=UTC)).asleep is False


def test_other_time_zones_give_the_same_answer() -> None:
    moment = datetime(2026, 10, 5, 13, 0, tzinfo=UTC)
    new_york = moment.astimezone(timezone(timedelta(hours=-4)))

    assert sleep_status(new_york) == sleep_status(moment)


def test_naive_datetime_is_rejected() -> None:
    with pytest.raises(ValueError):
        sleep_status(datetime(2026, 10, 5, 12, 0))
