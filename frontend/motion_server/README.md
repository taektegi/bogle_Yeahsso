# Bogle motion service

A child's drawing in, short animated clips out (jump, wave, dance), made
with Meta's [Animated Drawings](https://github.com/facebookresearch/AnimatedDrawings)
(MIT). The app works without it: friends whose drawings can't be animated,
or builds without a server, use the app's own motions.

## Run

```sh
motion_server/setup.sh   # once: conda env "bogle-motion", models (~700 MB)
motion_server/run.sh     # TorchServe + API on :8000, prints the address
```

Then build the app with the printed address, for example
`flutter run --dart-define=MOTION_SERVER=http://192.168.0.66:8000`.
The simulator can use `http://127.0.0.1:8000`; a real iPad needs the Mac's
address on the same Wi-Fi.

## API

| | |
|---|---|
| `POST /motions` (multipart `image`) | `{id, status}`; the same drawing always gets the same id |
| `GET /motions/{id}` | `{status, clips: {jump,wave,dance: {url, box}}, reason}` |
| `GET /motions/{id}/{clip}.gif` | transparent GIF, 720 px, ~2 s, ~1.7 MB |
| `GET /health` | `{ok, models}` |

`status` is `queued`, `working`, `ready`, `unsupported` or `failed`. `box` is
where the character moves within the clip (fractions), so the app can stand
it on its own floor. One drawing takes about 25 s on an M4 Pro (CPU).

## What it can animate

The models know two-legged figures with arms, drawn on plain paper.
`pipeline.py` checks the result before rendering and answers `unsupported`
with a reason:

- `not_humanoid`: no believable shoulders → hips → knees → feet (round
  blobs like 뭉글이, four-legged animals like 뚜치).
- `background`: lined or patterned paper leaked into the cut-out (네모린).
- `no_figure`: nothing found.

None of the three demo friends qualify, so they keep the app's motions; a
child's stick-figure or person drawing on plain paper does.

Drawings sent here are kept in `data/jobs/` (git-ignored). For a real
service, add guardian consent and a retention policy: photos of drawings can
include a child's name or face.
