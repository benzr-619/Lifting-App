---
name: frontend-conventions
description: JS idiom, render model, styling tokens, timers, and rehab exercise matching
metadata:
  type: project
---

# Frontend Conventions

## State & render model
- One global `var APP = {…}`. Mutate it, then call `render()`.
- `render()` rebuilds `#screen.innerHTML` from scratch — no reactivity, no diffing.
- `APP.screen` string (`today`, `checkin`, `workout`, `log_set`, `rest`, `calendar`, `rehab`) routes to a `r<Screen>()` function returning an HTML string.

## Naming
- Render functions: `r*` — `rToday`, `rWorkout`, `rRehabCard`, …
- Action/event handlers: plain verbs — `startWorkout`, `doLogSet`, `saveCheckin`
- Data-layer (Supabase): verb phrases — `loadBootData`, `saveDailyLog`, `updatePlanState`

## JS idiom
ES5-flavored throughout: `var`, `function`, `.map/.forEach`, string concatenation. No template literals, no JSX. `async/await` only for DB calls. Keep all new code in the same idiom.

## Styling
- CSS variables in `:root`: `--color-*`, `--radius-*`. Always use tokens, never raw hex.
- Full dark-mode override via `prefers-color-scheme`.
- App width-capped at 430px (phone).
- Icons: Tabler webfont `<i class="ti ti-*">`.
- UX targets: large tap targets, default reps pre-filled with +/- adjust, primary "Done" — gym-usable one-handed.

## Timers
- `setInterval` stored on `APP.timerInterval`; `render()` clears and re-arms it for `rest`/`rehab` screens.
- Accuracy anchored to `APP.timerEndTime` (absolute `Date.now()` ms) — remaining time recomputed each tick and on `visibilitychange`. Background throttling cannot cause drift.
- `playTimerDone()`: beeps using a **pre-baked `AudioBuffer`** (`BEEP_BUFFER`), generated on every `touchstart`. Uses `BufferSourceNode` playback — do NOT revert to oscillators, which silently fail on iOS when AudioContext is suspended mid-session.
- `ensureAudioCtx()` returns `APP.audioCtx`; if suspended, `resume()` is called but NOT awaited inline — `playTimerDone` awaits it via `.then(_play)`.
- Background alerts: service worker (`sw.js`) + Web Notifications API. Requires permission at workout start; PWA installed to home screen on iOS 16.4+.
- Rehab rest timer uses the same absolute-anchor pattern: `APP.rehabRestEndTime` + `APP.rehabRestActive`. See `.claude/rules/rehab.md` § Timed rehab rest timer.
- Band walk (weighted rehab) now also uses `rehabRestActive` for 60s/180s rest between sets — the render interval handles weighted exercises correctly as long as `rehab-rest-display` element ID is present.

## Workout session persistence
- `saveWorkoutProgress()` writes `{sessionId, exIndex, setLogged, loggedReps, loggedSkipped, skipReasons}` to `localStorage('lift_workout_progress')` after every set log.
- `loadBootData` queries for an open session today (`started_at` in date range, `completed_at IS NULL`) and restores progress from localStorage if `sessionId` matches.
- `startWorkout()`: if `APP.sessionId` is already set (restored), skips session creation and goes straight to workout screen with restored state.
- `finishSession()` clears `localStorage('lift_workout_progress')`.
- Today card shows amber "Resume →" with exercise count when `APP.sessionId !== null && !liftCompletedToday`.

## Rehab exercise matching
Behavior (`timed` / `weighted` / `free`) determined by substring-matching `rehab_exercise` text from `cycle_plan` against the `REHAB_EXERCISES` table via `rehabMatchExercise`. Rehab weights persist in `localStorage` per exercise key.

## Calendar data layer gotchas
- `lift.sessions` has **`started_at`** (not `created_at`) and `completed_at`. Selecting `created_at` causes a silent 400 from Supabase and returns `[]`.
- Do **not** chain `.not('completed_at', 'is', null)` with `.gte`/`.lte` on the same column — PostgREST returns 400. The range filters already exclude NULLs.
- PWA on iOS caches aggressively — service worker may serve stale `index.html` until the next cold launch. Expect a lag between GitHub Pages deploy and the phone reflecting changes.
