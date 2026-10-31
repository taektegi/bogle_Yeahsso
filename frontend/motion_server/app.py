"""Bogle motion service: a child's drawing in, short animated clips out.

    POST /motions              multipart "image" -> {"id", "status"}
    GET  /motions/{id}         -> {"id", "status", "clips": {name: {url, box}}, "reason"}
    GET  /motions/{id}/{clip}.gif
    GET  /health               -> {"ok", "models"}

status: queued -> working -> ready | unsupported | failed. "unsupported"
comes with a reason the app can show (not_humanoid, background, no_figure);
the app then keeps its own built-in motions.

Jobs run one at a time, each in its own `pipeline.py` process (rendering
needs a main thread). Results live in data/jobs/<id>/ and survive restarts.
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse

HERE = Path(__file__).resolve().parent
JOBS = HERE / "data" / "jobs"
JOBS.mkdir(parents=True, exist_ok=True)
MAX_BYTES = 12 * 1024 * 1024
TIMEOUT = 300

app = FastAPI(title="Bogle motion")
# Made at startup: on Python 3.8 a queue binds to the loop that exists when
# it is created, and at import time that is not uvicorn's.
_queue: asyncio.Queue | None = None


def _state(job: str) -> dict:
    d = JOBS / job
    result = d / "result.json"
    if result.exists():
        return json.loads(result.read_text())
    if (d / "working").exists():
        return {"status": "working"}
    if d.exists():
        return {"status": "queued"}
    raise HTTPException(404, "no such job")


def _run(job: str) -> None:
    d = JOBS / job
    (d / "working").touch()
    try:
        subprocess.run(
            [sys.executable, str(HERE / "pipeline.py"), str(d / "drawing.png"), str(d)],
            cwd=HERE / ".vendor" / "AnimatedDrawings" / "examples",
            stdout=open(d / "log.txt", "w"),
            stderr=subprocess.STDOUT,
            timeout=TIMEOUT,
            check=True,
        )
    except Exception as e:  # crash, timeout, TorchServe down
        if not (d / "result.json").exists():
            (d / "result.json").write_text(json.dumps({"status": "failed", "detail": str(e)}))
    finally:
        (d / "working").unlink(missing_ok=True)


async def _worker() -> None:
    assert _queue is not None
    while True:
        job = await _queue.get()
        try:
            # Python 3.8 (pinned by Animated Drawings) has no to_thread.
            await asyncio.get_running_loop().run_in_executor(None, _run, job)
        except Exception as e:  # keep serving the next jobs
            print(f"job {job} crashed: {e}", flush=True)
        finally:
            _queue.task_done()


@app.on_event("startup")
async def _start() -> None:
    global _queue
    _queue = asyncio.Queue()
    # Jobs interrupted by a restart go back in the queue.
    for d in sorted(JOBS.iterdir()):
        if d.is_dir() and not (d / "result.json").exists():
            (d / "working").unlink(missing_ok=True)
            _queue.put_nowait(d.name)
    asyncio.create_task(_worker())


@app.get("/health")
def health() -> dict:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8081/models", timeout=2) as r:
            models = [m["modelName"] for m in json.load(r)["models"]]
    except Exception:
        return {"ok": False, "models": []}
    return {"ok": len(models) == 2, "models": models}


@app.post("/motions")
async def create(image: UploadFile = File(...)) -> dict:
    data = await image.read()
    if not data:
        raise HTTPException(400, "empty image")
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "image too large")
    # The same drawing always maps to the same job, so re-sending it (or
    # opening the house again) reuses the clips instead of rendering again.
    job = hashlib.sha256(data).hexdigest()[:16]
    d = JOBS / job
    if d.exists():
        state = _state(job)
        if state["status"] != "failed":
            return {"id": job, "status": state["status"]}
        shutil.rmtree(d)
    d.mkdir()
    (d / "drawing.png").write_bytes(data)
    assert _queue is not None
    await _queue.put(job)
    return {"id": job, "status": "queued"}


@app.get("/motions/{job}")
def status(job: str, request: Request) -> dict:
    _safe(job)
    state = _state(job)
    clips = {
        name: {"url": str(request.url_for("clip", job=job, clip=name)), "box": meta["box"]}
        for name, meta in state.get("clips", {}).items()
    }
    return {"id": job, "status": state["status"], "clips": clips, "reason": state.get("reason")}


@app.get("/motions/{job}/{clip}.gif", name="clip")
def clip(job: str, clip: str) -> FileResponse:
    _safe(job)
    _safe(clip)
    path = JOBS / job / f"{clip}.gif"
    if not path.exists():
        raise HTTPException(404, "no such clip")
    return FileResponse(path, media_type="image/gif", headers={"Cache-Control": "max-age=31536000"})


def _safe(part: str) -> None:
    if not part.isalnum():
        raise HTTPException(400, "bad id")
