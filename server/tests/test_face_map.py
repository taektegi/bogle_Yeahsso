"""얼굴 지도: 앱이 간식을 입에 대고 얼굴을 움직이는 좌표가 그림과 맞는지."""

import math

from app import face_map, imaging
from tests.ai_support import FRONT_EYES, FRONT_MOUTH, SIDE_EYE, front_character, side_character


def close(a: float, b: float, tolerance: float) -> bool:
    return abs(a - b) <= tolerance


def test_front_character_eyes_and_mouth_are_found_without_a_model() -> None:
    image = front_character()

    face = face_map.estimate(image)

    assert face is not None
    assert face.facing == "front"
    assert len(face.eyes) == 2
    for found, (x, y, _) in zip(face.eyes, FRONT_EYES, strict=True):
        assert math.hypot(found.x - x, found.y - y) < 8
    # 입은 두 눈 사이 아래, 그려진 몸 위에
    assert face.mouth is not None
    assert close(face.mouth.cx, FRONT_MOUTH[0], 12)
    assert FRONT_EYES[0][1] < face.mouth.cy < FRONT_MOUTH[1] + 40
    assert imaging.alpha(image)[int(face.mouth.cy), int(face.mouth.cx)] > 0


def test_side_character_looks_toward_its_snout_and_eats_at_its_snout() -> None:
    image = side_character()

    face = face_map.estimate(image)

    assert face is not None
    assert face.facing == "left"
    [eye] = face.eyes
    assert math.hypot(eye.x - SIDE_EYE[0], eye.y - SIDE_EYE[1]) < 8
    # 입은 눈보다 주둥이 끝(왼쪽) 쪽, 눈보다 아래
    assert face.mouth is not None
    assert face.mouth.cx < eye.x
    assert face.mouth.cy > eye.y
    assert imaging.alpha(image)[int(face.mouth.cy), int(face.mouth.cx)] > 0


def test_a_model_mouth_in_thin_air_is_moved_onto_the_face() -> None:
    image = front_character()
    answer = {
        "size": [600, 600],
        "facing": "front",
        "head": [150, 120, 300, 300],
        "eyes": [[240, 250, 16], [360, 250, 16]],
        "mouth": [20, 20, 40, 14],  # 그림 밖 투명한 곳
        "cheeks": [],
    }

    face = face_map.refine(face_map.parse(answer, 600, 600), image)

    assert face is not None
    assert face.mouth is not None
    assert imaging.alpha(image)[int(face.mouth.cy), int(face.mouth.cx)] > 0
    assert face.mouth.cy > 250


def test_a_model_mouth_above_the_eyes_is_replaced() -> None:
    image = front_character()
    answer = {
        "size": [600, 600],
        "facing": "front",
        "eyes": [[240, 250, 16], [360, 250, 16]],
        "mouth": [300, 160, 40, 14],  # 이마
    }

    face = face_map.refine(face_map.parse(answer, 600, 600), image)

    assert face is not None and face.mouth is not None
    assert face.mouth.cy > 250
    assert "mouth_estimated" in face.notes or "mouth_moved" in face.notes


def test_slightly_off_model_eyes_snap_to_the_drawn_pupils() -> None:
    image = front_character()
    answer = {
        "size": [600, 600],
        "facing": "front",
        "eyes": [[252, 262, 16], [372, 240, 16]],  # 12px쯤 어긋남
        "mouth": [300, 330, 48, 20],
    }

    face = face_map.refine(face_map.parse(answer, 600, 600), image)

    assert face is not None
    for found, (x, y, _) in zip(face.eyes, FRONT_EYES, strict=True):
        assert math.hypot(found.x - x, found.y - y) < 6


def test_eyes_off_the_drawing_are_dropped_and_found_again() -> None:
    image = front_character()
    answer = {"size": [600, 600], "facing": "front", "eyes": [[30, 30, 10]]}

    face = face_map.refine(face_map.parse(answer, 600, 600), image)

    assert face is not None
    assert len(face.eyes) == 2
    assert all(imaging.alpha(image)[int(e.y), int(e.x)] > 0 for e in face.eyes)


def test_answers_for_a_resized_picture_are_scaled_back() -> None:
    image = front_character()
    # 모델이 300×300으로 줄여 보고 답한 경우
    answer = {"size": [300, 300], "facing": "front", "eyes": [[120, 125, 8], [180, 125, 8]]}

    face = face_map.refine(face_map.parse(answer, 600, 600), image)

    assert face is not None
    assert math.hypot(face.eyes[0].x - 240, face.eyes[0].y - 250) < 8


def test_the_head_box_covers_the_eyes_and_mouth_and_stays_on_the_picture() -> None:
    image = front_character()

    face = face_map.estimate(image)

    assert face is not None and face.head is not None and face.mouth is not None
    head = face.head
    assert head.x >= 0 and head.y >= 0 and head.right <= 600 and head.bottom <= 600
    for eye in face.eyes:
        assert head.x <= eye.x <= head.right and head.y <= eye.y <= head.bottom
    assert head.y <= face.mouth.cy <= head.bottom


def test_json_matches_the_app_face_map_format() -> None:
    data = face_map.estimate(front_character()).to_json()

    assert data["version"] == 1
    assert data["size"] == [600, 600]
    assert data["facing"] in ("front", "left", "right")
    assert len(data["head"]) == 4
    assert all(len(eye) == 3 for eye in data["eyes"])
    assert len(data["mouth"]) == 4  # 가운데 x, y, 너비, 높이


def test_garbage_from_the_model_falls_back_to_the_estimate() -> None:
    image = front_character()

    for junk in (None, "eyes", {"eyes": "here"}, {"mouth": [1, 2]}):
        face = face_map.refine(face_map.parse(junk, 600, 600), image)
        assert face is not None
        assert len(face.eyes) == 2
        assert face.mouth is not None
