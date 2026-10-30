# Loading motion handoff

## Figma source

File `bwWLmNFUlLdF4TTO6QlYR7`, wireframe page `26:2`:

- `250:2780` → `299:4308` → `299:4343`: lower slice, half-revealed, then full blue Bogle wordmark.
- `299:4379`: completed wordmark with five pastel bubbles.
- Notes `299:4170` and `299:4377`: soft transitions and exploratory bubble motion.
- No exported keyframe tracks or prototype reactions were present. Durations below are implementation choices responding to the request for fewer, slower bubbles, not exported Figma timing.

## Implemented behavior

- Original wordmark SVG, fixed 258 × 160 logical bounds, clipped bottom-to-top over 3.6 s using easeInOutCubic. Reveals once, never resets to imply generation progress.
- Copy follows the frames: `보글보글  · · ·` during the reveal, then `친구가 찾아오는 중  · · ·` (36 pt, `#8BA2FF`). Bagel Fat One (OFL, bundled) stands in for the Figma-only SD WalkieTalkie Round. No subtitle until a long wait or failure.
- Five original Figma bubbles at their Figma sizes (225–467 pt) rise through the whole screen, over the wordmark and copy as in `299:4379`, instead of being kept away from it. Each rises at constant speed (10–13 s per full screen height, ~2× the previous pace), with 16 pt sway and a slight jelly squash. Phases are chosen so the bubbles line up exactly as in `299:4379` when the reveal ends; later loops drift up to 70 pt sideways so repeats don't look stamped.
- Tapping a bubble splits it into two 66 % bubbles that spring apart (easeOutBack/elasticOut) and keep rising a little faster, with a soft ring and sparkles. 225 → 148 → 98 pt; bubbles below 90 pt just pop. At most 32 split bubbles. A tapped Figma bubble returns on its next loop.
- Back/retry controls stay above the bubbles so taps never land on a bubble instead.
- Reduce Motion shows the static Figma composition; taps split instantly without starting a ticker. App backgrounding and failure stop the ticker.
- Copy changes at 30 s and 75 s without fabricated percentages or promises about remaining time. A 5-minute unanswered request offers retry rather than an infinite wait; tune this policy when the real service SLA is known.
- Completion comes from `CharacterGenerationJob.completed`. Retry invalidates earlier attempts. Disposal/cancel invalidates completion and calls the job's cancellation hook.
- Returning to the studio preserves its in-memory drawing. It is not persistent storage, nor a guarantee of server-side cancellation.

## Frontend-only boundary

The default `DemoCharacterGenerationJob` completes after 18 s. It makes no network call and does not generate a character. Inject `LoadingScreen.startGeneration` to test longer jobs/errors. When integrating an AI backend, implement the job adapter, request/result schemas, asset transfer to setup, and actual cancellation behavior. These backend features are intentionally not implemented.

## Verification

- `flutter test`: logo clip geometry, >75 s waiting, successful completion, error/retry, reduced motion, 5-minute timeout, stale completion, cancellation, existing studio/archive regressions.
- `integration_test/loading_flow_test.dart`: iPad reveal screenshots, return to drawn draft, demo-to-setup navigation, 32 s wait spanning a full bubble cycle, frame timing capture.
- `artifacts/loading-verification.json` contains debug-simulator timing, not a physical iPad FPS guarantee.
