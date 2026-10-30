"""One drawing -> motion clips, run as its own process.

    python pipeline.py <drawing.png> <out_dir>

1. Finds, cuts out and rigs the character with Meta's Animated Drawings
   (needs TorchServe on :8080 with both models).
2. Checks the result is worth animating (see `check`), because the models
   only know two-legged, arms-out figures drawn on plain paper.
3. Renders each clip in CLIPS as a small transparent GIF.

Writes out_dir/result.json: {"status": "ready", "clips": [...]} or
{"status": "unsupported", "reason": ...}. Rendering uses OpenGL, which on
macOS must run on the process's main thread; that is why this is a
separate process rather than a thread in the API server.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import yaml
from PIL import Image

HERE = Path(__file__).resolve().parent
AD = HERE / ".vendor" / "AnimatedDrawings"
sys.path.insert(0, str(AD / "examples"))

# Short loops cut from Meta's motion-capture clips (fair1 skeleton).
CLIPS = {
    "jump": ("jumping.bvh", 150, 250),
    "wave": ("wave_hello.bvh", 0, 110),
    "dance": ("dab.bvh", 0, 110),
}
SIZE = 360  # rendered square, in pixels
EVERY = 2  # keep every other frame: 30 fps -> 15 fps, half the size


def check(out: Path) -> str | None:
    """Why this drawing can't be animated, or None if it can."""
    cfg = yaml.safe_load((out / "char_cfg.yaml").read_text())
    h, w = cfg["height"], cfg["width"]
    joints = {j["name"]: np.array(j["loc"], float) for j in cfg["skeleton"]}

    # The joints should spread over the figure, not bunch up in a corner.
    pts = np.stack(list(joints.values()))
    span = pts.max(0) - pts.min(0)
    if span[1] < h * 0.45 or span[0] < w * 0.2:
        return "not_humanoid"

    # Top to bottom: shoulders, hips, knees, feet — on both sides.
    for side in ("left", "right"):
        ys = [joints[f"{side}_{j}"][1] for j in ("shoulder", "hip", "knee", "foot")]
        if not all(a < b for a, b in zip(ys, ys[1:])):
            return "not_humanoid"

    # Lined or patterned paper leaks into the cut-out as stripes running out
    # to the edges of the crop. A real outline touches a crop edge only in a
    # stretch or two (a hand, a foot); paper lines touch it again and again.
    mask = np.array(Image.open(out / "mask.png").convert("L")) > 127
    touches = [mask[:, :3].any(1), mask[:, -3:].any(1)]
    if sum(_runs(t) for t in touches) >= 6:
        return "background"
    return None


def _runs(flags: np.ndarray) -> int:
    """How many separate stretches of True there are."""
    f = flags.astype(np.int8)
    return int(f[0] + (np.diff(f) == 1).sum())


def render(out: Path, name: str, bvh: str, start: int, end: int) -> list[float]:
    """Renders one clip; returns where the character moves within it."""
    import animated_drawings.render

    motion = out / f"{name}_motion.yaml"
    base = yaml.safe_load((AD / "examples/config/motion" / f"{Path(bvh).stem}.yaml").read_text())
    base.update(
        filepath=str(AD / "examples/bvh/fair1" / bvh),
        start_frame_idx=start,
        end_frame_idx=end,
    )
    motion.write_text(yaml.dump(base))

    gif = out / f"{name}.gif"
    mvc = out / f"{name}_mvc.yaml"
    mvc.write_text(
        yaml.dump(
            {
                "scene": {
                    "ANIMATED_CHARACTERS": [
                        {
                            "character_cfg": str(out / "char_cfg.yaml"),
                            "motion_cfg": str(motion),
                            "retarget_cfg": str(AD / "examples/config/retarget/fair1_ppf.yaml"),
                        }
                    ]
                },
                "view": {"WINDOW_DIMENSIONS": [SIZE, SIZE]},
                "controller": {"MODE": "video_render", "OUTPUT_VIDEO_PATH": str(gif)},
            }
        )
    )
    animated_drawings.render.start(str(mvc))
    return _thin(gif)


def _thin(gif: Path) -> list[float]:
    """Drops every other frame (doubling each kept frame's duration) and
    returns the box the character stays within over the whole clip, as
    [left, top, right, bottom] fractions, so the app can stand it on its
    own floor at its own size."""
    src = Image.open(gif)
    frames, durations = [], []
    box = None
    for i in range(src.n_frames):
        src.seek(i)
        if i % EVERY == 0:
            frame = src.convert("RGBA")
            frames.append(frame)
            durations.append(src.info.get("duration", 33) * EVERY)
            b = frame.getchannel("A").getbbox()
            if b:
                box = b if box is None else (
                    min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3])
                )
    frames[0].save(
        gif,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        disposal=2,
        transparency=0,
    )
    w, h = frames[0].size
    box = box or (0, 0, w, h)
    return [box[0] / w, box[1] / h, box[2] / w, box[3] / h]


def main(image: str, out_dir: str) -> None:
    from image_to_annotations import image_to_annotations

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    result = out / "result.json"
    try:
        image_to_annotations(image, str(out))
    except Exception as e:  # no figure found, model errors, ...
        result.write_text(json.dumps({"status": "unsupported", "reason": "no_figure", "detail": str(e)}))
        return
    reason = check(out)
    if reason:
        result.write_text(json.dumps({"status": "unsupported", "reason": reason}))
        return
    clips = {
        name: {"box": render(out, name, bvh, start, end)}
        for name, (bvh, start, end) in CLIPS.items()
    }
    result.write_text(json.dumps({"status": "ready", "clips": clips}))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
