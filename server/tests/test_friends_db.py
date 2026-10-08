"""친구 만들기·고치기, 친구마다의 수면 시간, 대화, 모션을 실제 PostgreSQL로 확인한다."""

import io
from datetime import datetime

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.ai import AiUnavailable, get_ai
from app.clock import get_now
from app.config import Settings, get_settings
from app.db import Database, get_database
from app.motion import process_motion
from app.rate_limit import message_limiter
from app.repositories.motions import MotionRepository
from app.storage import get_storage
from tests.ai_support import FakeModerator, FakeWriter, fake_ai
from tests.conftest import JWT_SECRET, SUPABASE_URL
from tests.db_support import FakeStorage, make_generation_job, make_user
from tests.tokens import bearer, hs256_token

FACE = {"version": 1, "size": [640, 480], "facing": "front", "eyes": [[300, 200, 12]],
        "mouth": [320, 260, 40, 14], "head": [200, 100, 240, 220], "cheeks": []}  # fmt: skip
AFTERNOON = "2026-10-08T05:00:00+00:00"  # 14:00 KST
NIGHT = "2026-10-08T14:00:00+00:00"  # 23:00 KST


@pytest.fixture(autouse=True)
def _fresh_limits():
    message_limiter._hits.clear()


@pytest.fixture
def storage() -> FakeStorage:
    return FakeStorage()


@pytest.fixture
def writer() -> FakeWriter:
    return FakeWriter()


@pytest.fixture
def api(app, client: TestClient, database: Database, storage, writer) -> TestClient:
    app.dependency_overrides[get_database] = lambda: database
    app.dependency_overrides[get_storage] = lambda: storage
    app.dependency_overrides[get_ai] = lambda: fake_ai(
        writer=writer, moderator=FakeModerator(banned=("나쁜말",))
    )
    app.dependency_overrides[get_now] = lambda: datetime.fromisoformat(AFTERNOON)
    return client


def auth(user) -> dict[str, str]:
    return bearer(hs256_token(sub=str(user)))


def create(api, user, job, key: str = "friend-key-01", **overrides):
    body = {
        "generationJobId": str(job),
        "name": "구름이",
        "personality": "엉뚱한 상상을 좋아해요",
        "favoriteThings": ["구름", "사과"],
        "speechStyle": "~지요!",
        **overrides,
    }
    return api.post("/v1/characters", headers={**auth(user), "Idempotency-Key": key}, json=body)


# ---------------------------------------------------------------------------
# 만들기
# ---------------------------------------------------------------------------


def test_a_friend_is_made_from_a_finished_job_with_its_face_map(api, seed_conn) -> None:
    user = make_user(seed_conn)
    job = make_generation_job(seed_conn, user, face=FACE)

    response = create(api, user, job)

    assert response.status_code == 201, response.text
    friend = response.json()
    assert friend["name"] == "구름이"
    assert friend["personality"] == "엉뚱한 상상을 좋아해요"
    assert friend["personalityLabel"] == "엉뚱한 상상을 좋아해요"
    assert friend["personalityType"] == "custom"
    assert friend["introduction"] == "구름 위에서 놀다 왔어요!"  # AI가 쓴 소개
    assert friend["face"]["mouth"] == [320, 260, 40, 14]
    assert (friend["bedtime"], friend["wakeTime"]) == (22 * 60, 6 * 60)
    assert friend["art"]["contentType"] == "image/png"


def test_a_personality_type_code_still_works(api, seed_conn) -> None:
    user = make_user(seed_conn)
    job = make_generation_job(seed_conn, user)

    friend = create(api, user, job, personality=None, personalityType="calm").json()

    assert friend["personalityType"] == "calm"
    assert friend["personalityLabel"] == "느긋하고 차분해요"


def test_the_same_key_returns_the_same_friend(api, seed_conn) -> None:
    user = make_user(seed_conn)
    job = make_generation_job(seed_conn, user)

    first = create(api, user, job).json()
    again = create(api, user, job)

    assert again.status_code == 200
    assert again.json()["id"] == first["id"]


def test_a_job_makes_only_one_friend(api, seed_conn) -> None:
    user = make_user(seed_conn)
    job = make_generation_job(seed_conn, user)
    create(api, user, job, key="friend-key-01")

    response = create(api, user, job, key="friend-key-02")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "generation_job_already_used"


@pytest.mark.parametrize("status", ["queued", "processing", "failed", "cancelled"])
def test_an_unfinished_job_cannot_become_a_friend(api, seed_conn, status) -> None:
    user = make_user(seed_conn)
    job = make_generation_job(seed_conn, user, status=status)

    response = create(api, user, job)

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "generation_not_ready"


def test_someone_elses_job_is_not_found(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)

    response = create(api, me, make_generation_job(seed_conn, other))

    assert response.status_code == 404


@pytest.mark.parametrize(
    ("overrides", "field", "kind"),
    [
        ({"name": "   "}, "name", "string_too_short"),
        ({"name": "가" * 13}, "name", "string_too_long"),
        ({"favoriteThings": []}, "favoriteThings", "too_short"),
        ({"favoriteThings": ["우주"]}, "favoriteThings", "unknown_item"),
        ({"favoriteThings": ["구름", "구름"]}, "favoriteThings", "duplicate_item"),
        ({"speechStyle": "존댓말"}, "speechStyle", "literal_error"),
        ({"personality": None}, "personality", "missing"),
        ({"bedtime": 1440}, "bedtime", "less_than_equal"),
    ],
)
def test_invalid_settings_say_which_field(api, seed_conn, overrides, field, kind) -> None:
    user = make_user(seed_conn)

    response = create(api, user, make_generation_job(seed_conn, user), **overrides)

    assert response.status_code == 422
    assert response.json()["error"]["fieldErrors"].get(field) == kind


def test_a_failing_writer_leaves_the_introduction_empty(api, seed_conn, writer) -> None:
    user = make_user(seed_conn)
    writer.error = AiUnavailable("down")

    friend = create(api, user, make_generation_job(seed_conn, user)).json()

    assert friend["introduction"] == ""


def test_without_a_motion_service_the_friend_uses_the_app_motions(api, seed_conn) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()

    motion = api.get(f"/v1/characters/{friend['id']}/motion", headers=auth(user)).json()

    assert motion == {"status": "unsupported", "reason": "disabled", "clips": {}}


# ---------------------------------------------------------------------------
# 고치기·수면 시간
# ---------------------------------------------------------------------------


def test_the_edit_screen_changes_only_what_it_sends(api, seed_conn) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()

    response = api.patch(
        f"/v1/characters/{friend['id']}",
        headers=auth(user),
        json={"name": "뭉게", "introduction": "하늘에서 왔어", "speechStyle": "반말"},
    )

    assert response.status_code == 200
    changed = response.json()
    assert (changed["name"], changed["introduction"], changed["speechStyle"]) == (
        "뭉게",
        "하늘에서 왔어",
        "반말",
    )
    assert changed["personality"] == friend["personality"]
    assert changed["face"] == friend["face"]


def test_each_friend_sleeps_on_its_own_schedule(api, app, seed_conn) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()
    path = f"/v1/characters/{friend['id']}"

    api.patch(path, headers=auth(user), json={"bedtime": 13 * 60, "wakeTime": 15 * 60})
    status = api.get(f"{path}/status", headers=auth(user)).json()

    assert status["asleep"] is True  # 14:00 KST는 이 친구의 낮잠 시간
    assert status["nextChangeAt"] == "2026-10-08T06:00:00Z"  # 15:00 KST


def test_someone_elses_friend_cannot_be_edited(api, seed_conn) -> None:
    me, other = make_user(seed_conn), make_user(seed_conn)
    friend = create(api, other, make_generation_job(seed_conn, other)).json()

    response = api.patch(f"/v1/characters/{friend['id']}", headers=auth(me), json={"name": "x"})

    assert response.status_code == 404


# ---------------------------------------------------------------------------
# 대화
# ---------------------------------------------------------------------------


def say(api, user, friend_id, text: str, message_id: str = "msg-000001"):
    return api.post(
        f"/v1/characters/{friend_id}/messages",
        headers=auth(user),
        json={"clientMessageId": message_id, "text": text},
    )


def test_the_friend_answers_and_the_chat_is_kept(api, seed_conn, writer) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()

    first = say(api, user, friend["id"], "오늘 뭐 했어?", "msg-000001").json()
    say(api, user, friend["id"], "같이 놀자!", "msg-000002")

    assert first["userMessage"]["text"] == "오늘 뭐 했어?"
    assert first["assistantMessage"] == {
        **first["assistantMessage"],
        "role": "assistant",
        "text": "구름 구경했지요!",
        "source": "ai",
    }
    # 두 번째 질문 때 AI는 앞의 대화를 문맥으로 받았다.
    assert [t.text for t in writer.seen[-1]] == ["오늘 뭐 했어?", "구름 구경했지요!"]
    history = api.get(f"/v1/characters/{friend['id']}/messages", headers=auth(user)).json()
    assert [m["text"] for m in history["items"]] == [
        "구름 구경했지요!",
        "같이 놀자!",
        "구름 구경했지요!",
        "오늘 뭐 했어?",
    ]


def test_a_resend_gets_the_same_answer_without_asking_again(api, seed_conn, writer) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()

    first = say(api, user, friend["id"], "안녕").json()
    writer.answer = "다른 대답"
    again = say(api, user, friend["id"], "안녕").json()

    assert again == first


def test_the_same_message_id_with_other_text_is_a_conflict(api, seed_conn) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()
    say(api, user, friend["id"], "안녕")

    response = say(api, user, friend["id"], "잘 가")

    assert response.status_code == 409


def test_flagged_words_and_ai_failures_get_a_scripted_answer(api, seed_conn, writer) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()

    flagged = say(api, user, friend["id"], "나쁜말 해 봐", "msg-000001").json()
    writer.error = AiUnavailable("down")
    failed = say(api, user, friend["id"], "사랑해!", "msg-000002").json()

    for answer in (flagged, failed):
        assert answer["assistantMessage"]["source"] == "script"
        assert answer["assistantMessage"]["text"].endswith("!")
    assert "지요" in failed["assistantMessage"]["text"]  # 친구의 말투


def test_an_asleep_friend_does_not_answer(api, app, seed_conn) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()
    app.dependency_overrides[get_now] = lambda: datetime.fromisoformat(NIGHT)

    response = say(api, user, friend["id"], "안녕")

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "character_asleep"


def test_chat_history_pages_by_cursor(api, seed_conn) -> None:
    user = make_user(seed_conn)
    friend = create(api, user, make_generation_job(seed_conn, user)).json()
    for i in range(3):
        say(api, user, friend["id"], f"메시지 {i}", f"msg-00000{i}")
    path = f"/v1/characters/{friend['id']}/messages"

    first = api.get(path, headers=auth(user), params={"limit": 4}).json()
    rest = api.get(
        path, headers=auth(user), params={"limit": 4, "before": first["nextCursor"]}
    ).json()

    assert len(first["items"]) == 4 and first["nextCursor"]
    assert len(rest["items"]) == 2 and rest["nextCursor"] is None
    texts = [m["text"] for m in first["items"] + rest["items"]]
    assert texts[-1] == "메시지 0"


# ---------------------------------------------------------------------------
# 모션
# ---------------------------------------------------------------------------


def gif(width: int = 72, height: int = 48) -> bytes:
    out = io.BytesIO()
    Image.new("P", (width, height)).save(out, format="GIF")
    return out.getvalue()


class FakeMotionService:
    def __init__(self, states: list[dict]) -> None:
        self.states = states
        self.submitted: list[bytes] = []

    def submit(self, png: bytes) -> str:
        self.submitted.append(png)
        return "remote-1"

    def status(self, remote_id: str) -> dict:
        return self.states.pop(0) if len(self.states) > 1 else self.states[0]

    def fetch(self, url: str) -> bytes:
        return gif()


@pytest.fixture
def with_motion(app, settings: Settings):
    settings = Settings(
        _env_file=None,
        supabase_url=SUPABASE_URL,
        supabase_jwt_secret=JWT_SECRET,
        motion_service_url="http://motion.test",
    )
    app.dependency_overrides[get_settings] = lambda: settings


def _friend_with_motion(api, seed_conn, storage, user):
    friend = create(api, user, make_generation_job(seed_conn, user)).json()
    art_path = seed_conn.execute(
        "select a.storage_path from public.friends f join public.assets a"
        " on a.id = f.art_asset_id where f.id = %s",
        (friend["id"],),
    ).fetchone()["storage_path"]
    buffer = io.BytesIO()
    Image.new("RGBA", (300, 400), (120, 180, 240, 255)).save(buffer, format="PNG")
    storage.uploaded[art_path] = (buffer.getvalue(), "image/png")
    return friend


def test_ready_clips_are_stored_and_signed(api, seed_conn, storage, database, with_motion) -> None:
    user = make_user(seed_conn)
    friend = _friend_with_motion(api, seed_conn, storage, user)
    service = FakeMotionService(
        [
            {"status": "working"},
            {
                "status": "ready",
                "clips": {
                    "jump": {"url": "http://motion.test/jump.gif", "box": [0.1, 0.05, 0.9, 0.95]},
                    "wave": {"url": "http://motion.test/wave.gif", "box": [0.1, 0.05, 0.9, 0.95]},
                },
            },
        ]
    )
    repo = MotionRepository(database)
    work = repo.claim_next()
    assert work is not None and str(work.job.character_id) == friend["id"]

    process_motion(work, repo=repo, storage=storage, client=service, timeout=60, retries=2,
                   sleep=lambda _: None)  # fmt: skip

    motion = api.get(f"/v1/characters/{friend['id']}/motion", headers=auth(user)).json()
    assert motion["status"] == "ready"
    assert set(motion["clips"]) == {"jump", "wave"}
    assert motion["clips"]["jump"]["box"] == [0.1, 0.05, 0.9, 0.95]
    assert motion["clips"]["jump"]["url"].startswith("https://storage.test/signed/")
    # 흰 종이에 얹어 보낸다
    sent = Image.open(io.BytesIO(service.submitted[0]))
    assert sent.getpixel((2, 2)) == (255, 255, 255)

    # 친구를 지우면 클립 GIF도 지워진다
    api.delete(f"/v1/characters/{friend['id']}", headers=auth(user))
    removed = [path for batch in storage.removed for path in batch]
    assert sum(path.endswith(".gif") for path in removed) == 2


def test_a_drawing_the_motion_model_cannot_rig_falls_back_to_app_motions(
    api, seed_conn, storage, database, with_motion
) -> None:
    user = make_user(seed_conn)
    friend = _friend_with_motion(api, seed_conn, storage, user)
    service = FakeMotionService([{"status": "unsupported", "reason": "not_humanoid"}])
    repo = MotionRepository(database)

    process_motion(repo.claim_next(), repo=repo, storage=storage, client=service, timeout=60,
                   retries=2, sleep=lambda _: None)  # fmt: skip

    motion = api.get(f"/v1/characters/{friend['id']}/motion", headers=auth(user)).json()
    assert motion == {"status": "unsupported", "reason": "not_humanoid", "clips": {}}
