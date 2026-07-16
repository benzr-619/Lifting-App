---
name: frontend-conventions
description: JS idiom, render model, styling tokens, timers, and rehab exercise matching
metadata:
  type: project
---

# Frontend Conventions

## Hidden state-editor panel (`showStatePanel`)
Manual override sheet for fixing mis-recorded days without touching Supabase by hand. **Opened by long-pressing the `Phase · Day` badge** (`id="phase-badge"` in `rToday`) — `badgePressStart`/`badgePressEnd` arm a 600ms `BADGE_PRESS_TIMER` via inline `ontouchstart`/`onmousedown` string handlers (cancel on touchmove/mouseleave). Uses the same bottom-sheet overlay idiom as `showSkipMenu` (`id="state-overlay"`, backdrop-click dismiss).
- **Module globals:** `STATE_DRAFT` (working copy of the cursor while editing), `STATE_SESSIONS` (recent sessions loaded for the list). Both cleared by `closeStatePanel()`.
- **Cursor editor:** ± steppers (`stateAdj` clamps) for `current_phase` (1–7), `current_cycle_day` (1–8), `current_gym_day` (1–3). `saveStateCursor()` → `updatePlanState(...)` then `loadBootData()` for a full refresh. Save button disabled until the draft differs from `APP.planState`.
- **Lift toggle:** `stateMarkLiftDone` / `stateMarkLiftNotDone` flip `APP.liftCompletedToday` and write/clear `lift_gym_day_pending` (done-write mirrors `finishSession`: `nextGymDay = (current_gym_day % 3) + 1`).
- **Recent sessions:** last 5 via `db.from('sessions')`. Re-date uses `<input type="date">` → `stateRedateSession` preserves time-of-day (only sub-second µs drop) so the stored instant's local day moves cleanly; both `started_at` and `completed_at` are patched. Delete → `db.delete` (relies on `session_sets.session_id_fkey ON DELETE CASCADE`). `refreshStateSheet()` re-renders only the sheet body in place. `localDateFromTs(ts)` mirrors `localDateStr` for a timestamp.

## Deferred day-advance — two independent pending objects
`lift_advance_pending` (old combined key) has been replaced by two separate localStorage entries:

**`lift_gym_day_pending`: `{ date, nextGymDay }`**
Written by `finishSession`, `stateMarkLiftDone`, and the DB-fallback block.
- Same-day stale guard: discard if `nextGymDay === current_gym_day` (manually advanced via state panel).
- Next-day: apply `updatePlanState({ current_gym_day: nextGymDay })` then delete.

**`lift_cycle_day_pending`: `{ date }`**
Written by `maybeWriteCycleDayAdvance` (called from `toggleRun`, `logAlternateActivity`, `toggleRehab`, `rehabMarkComplete` — all day types).
- Same-day: no-op — just keep it.
- Next-day: call `advanceCycleDay()` then delete. Buffer-day suppression applies here (seaBufElapsed === 1 → delete without advancing).

The two objects apply independently. The cycle cursor can advance without the gym-day cursor moving, and vice versa. `APP.liftCompletedToday` is set only by the gym-day pending (lift actually happened), not by the cycle-day pending.

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
- **SW path must be RELATIVE.** App is served from a GitHub Pages subpath (`https://benzr-619.github.io/Lifting-App/`). `navigator.serviceWorker.register('/sw.js')` resolves to the domain root → 404 → SW never registers → zero background notifications. Use `register('sw.js')`. Same for `sw.js` internals: `icon: 'logo.png'` and `clients.openWindow('./')`, never a leading `/`. (Fixed 2026-06-13 — was the root cause of "no chimes on phone".)
- **iOS background reality:** a service-worker `setTimeout` is killed within seconds of the screen locking, and backgrounded JS halts entirely (audio suspends too). The SW scheduled notification is best-effort only — do NOT rely on it as the primary alert. The reliable mechanism for the short (60–180s) rest timers is the **Screen Wake Lock** (below), which keeps the in-page interval + `playTimerDone()` chime alive. True locked-screen alerts would need server Web Push (VAPID) — deliberately not built; disproportionate for sub-3-minute rests.

## Screen Wake Lock (`requestWakeLock` / `releaseWakeLock` / `aTimerIsRunning`)
- `navigator.wakeLock.request('screen')` held in module-global `WAKE_LOCK` while any countdown runs, so the screen stays on and the chime fires. iOS 16.4+.
- Driven from the end of `render()`: `if (aTimerIsRunning()) requestWakeLock(); else releaseWakeLock();` — covers rest, rehab set, and rehab rest timers, and auto-releases the moment no timer is active (incl. skips, since `render()` always runs).
- Wake locks auto-release when the page is hidden; the `visibilitychange→visible` handler re-acquires if `aTimerIsRunning()`.
- `requestWakeLock` is idempotent (no-op if `WAKE_LOCK` already held) and fails silently on unsupported browsers.

- Rehab rest timer uses the same absolute-anchor pattern: `APP.rehabRestEndTime` + `APP.rehabRestActive`. See `.claude/rules/rehab.md` § Timed rehab rest timer.
- Band walk (weighted rehab) now also uses `rehabRestActive` for 60s/180s rest between sets — the render interval handles weighted exercises correctly as long as `rehab-rest-display` element ID is present.

## Workout session persistence
- `saveWorkoutProgress()` writes `{sessionId, exIndex, setLogged, loggedReps, loggedSkipped, skipReasons}` to `localStorage('lift_workout_progress')` after every set log.
- `loadBootData` queries for an open session today (`started_at` in date range, `completed_at IS NULL`) and restores progress from localStorage if `sessionId` matches.
- `startWorkout()`: if `APP.sessionId` is already set (restored), skips session creation and goes straight to workout screen with restored state.
- `finishSession()` clears `localStorage('lift_workout_progress')`.
- Today card shows amber "Resume →" with exercise count when `APP.sessionId !== null && !liftCompletedToday`.

## Seam buffer day (`isBufferDay`, `bufferRehab`)
At cycle 8→1 boundary crossings where the outgoing day AND incoming day 1 both have `run_miles` (seam days: day_numbers 16, 40, 48, 56 = `SEAM_BUFFER_OUTGOING_DAYS`), a standalone buffer day is inserted between them. `current_cycle_day` stays at **8** through the buffer day — the 8→1 roll is deferred to the calendar day after.

**Detection** (`loadBootData`, runs before advance-pending processing): if `current_cycle_day === 8` and today's phase is a seam boundary phase, find the cycle-start anchor via `getCycleStartDate(current_phase)` (see below), then query `daily_log` for the most recent row within **this cycle pass only** (`.gte('log_date', cycleStartDate)`) with `plan_phase = current_phase, plan_cycle_day = 8, run_completed = true, rehab_completed = true`. Compute `seaBufElapsed` = days between that anchor and today. If `getCycleStartDate` returns null (no day-1 entry yet), skip detection entirely (`seaBufElapsed` stays -1).
- `seaBufElapsed === 1` → today is the buffer day: set `APP.isBufferDay = true`, suppress `lift_cycle_day_pending` (delete it without advancing), query adjacent rehab.
- `seaBufElapsed >= 2` → buffer day has passed: apply deferred 8→1 roll via `advanceCycleDay()` if no cycle advance was already applied. **Safety rail:** if `seaBufElapsed > 7`, log a console warning and skip the auto-roll — an implausibly large elapsed signals something wrong upstream that should surface rather than silently mutate `plan_state`. `lift_gym_day_pending` is unaffected by buffer-day logic.

**Bug fixed 2026-07-14:** The anchor query was previously unscoped (no `.gte('log_date', cycleStartDate)`). When the same seam-boundary phase was entered for a second pass (because `clean_cycles_required > 1`), the query matched a day-8 completion from the prior pass, computed a large `seaBufElapsed`, and immediately fired a spurious 8→1 roll on boot — before the current pass had even reached day 8. Scoping to the current cycle pass via `getCycleStartDate` prevents this.

**`getCycleStartDate(phase)` helper** — shared by `recomputeCycleRestDays`, `checkStructuralWindows`, and seam-buffer detection. Returns the most recent `log_date` where `plan_phase = phase AND plan_cycle_day = 1`, or `null` if no such row exists. All three callers scope their queries to `>= cycleStartDate` so they reflect the current pass only, not accumulated history.

**Buffer day state**: `APP.isBufferDay = true`, `APP.bufferRehab` = nearest preceding lift-only (is_lift_day=true, run_miles IS NULL) day's rehab, queried via `.lte('day_number', outgoingDayNum)`. No localStorage used — state is fully DB-derived on every boot.

**UI on buffer days**: blue dashed lift card ("Optional"), **no run card**, rehab card uses `bufferRehab` via `activeRehabLabel()`/`activeRehabTiming()`. Tapping "Lift →" calls `startWorkout()` as normal — `finishSession()` writes `lift_gym_day_pending` for the gym_day advance; `maybeWriteCycleDayAdvance()` returns early (buffer-day guard) so no `lift_cycle_day_pending` is written. Skipping (doing nothing) has zero effect on cycle cursor, rest days, or cleanliness — the deferred 8→1 roll fires via `seaBufElapsed >= 2` at next boot.

Exercise loading and lift card rendering both guard on `APP.todayPlan.is_lift_day || APP.isBufferDay` since the cursor day (e.g., day 16) has `is_lift_day = false`.

All `rehabMatchExercise(APP.todayPlan.rehab_exercise)` calls use `activeRehabLabel()` instead; all `rehab_timing` references use `activeRehabTiming()`. This covers render intervals, `goRehab`, `rehabTimerSkip`, `rehabSkipRest`, `rehabWeightAdj`, `rehabLogSet`, and `rRehab`.

## Rehab exercise matching
Behavior (`timed` / `weighted` / `free`) determined by substring-matching `rehab_exercise` text from `cycle_plan` against the `REHAB_EXERCISES` table via `rehabMatchExercise`. Rehab weights persist in `localStorage` per exercise key.

## Ad-hoc lift card (`rAdHocLiftCard`)
On non-lift, non-buffer days, `rToday()` always renders `rAdHocLiftCard()` — a dashed/optional card identical in structure to `rBufferDayCard()`. Tapping it calls `startWorkout()` unchanged; `finishSession()` writes `lift_gym_day_pending` as normal. The card is always shown (even when done, dimmed). No readiness/deload gate — always available.

## Alternate activity logging (`ALTERNATE_ACTIVITIES`, `showActivityPicker`, `logAlternateActivity`)
`ALTERNATE_ACTIVITIES` is a module-level array of `{type, label, icon}`. Currently: `[{type:'tennis', label:'Tennis', icon:'ti-ball-tennis'}]`. Add rows here to extend — no other code changes needed for either mechanism below.

When a run day is not yet logged, a "Log something else instead →" text button appears below the run card. Tapping it opens a bottom-sheet overlay (`activity-overlay`) listing the preset alternatives. Selecting one calls `logAlternateActivity(type)`, which sets `run_completed = true` AND `activity_type = type` — so all cursor/gate/exemption logic (which only checks `run_completed`) is unaffected. `toggleRun()` also sets `activity_type = 'run'` when toggling on.

`daily_log.activity_type TEXT DEFAULT 'run'` was added in migration 006. The run card and calendar detail view both reflect the alternate activity label/icon when `activity_type !== 'run'`.

## Cross-training log (`showCrossTrainingPicker`, `logCrossTraining`, `rCrossTrainingCard`)
**Distinct from** `logAlternateActivity` — used on days with **no scheduled run** (`APP.todayPlan.run_miles === null`). Sets `daily_log.cross_training_completed = true` and `activity_type = type`; does **not** touch `run_completed` (stays false). No effect on cursor, flare logic, or structural test windows.

`rCrossTrainingCard()` is always rendered in `rToday()` when `!tp.run_miles && !APP.isBufferDay` — same always-visible/dimmed-when-done pattern as `rAdHocLiftCard`. Reuses the same `activity-overlay` bottom-sheet and `ALTERNATE_ACTIVITIES` list, but routes to `logCrossTraining` instead of `logAlternateActivity`.

`logCrossTraining(type)` upserts into `daily_log` (same `onConflict: 'user_id,log_date'` as `saveDailyLog`), then refreshes `APP.todayLog = data` and calls `render()`. Does not call `maybeWriteCycleDayAdvance()` — cross-training does not satisfy the run/rehab completion gate.

`recomputeCycleRestDays()` treats `cross_training_completed = true` as an active day — a day with cross-training does not count as a rest day even if `run_completed` and `rehab_completed` are both false.

Next-day heads-up: `APP.crossTrainingHeadsUp` (bool, set in `loadBootData` by querying yesterday's log) → when true and today has `run_miles`, `rToday()` renders an info banner above the run card ("consider easing today's run"). Purely advisory — no plan_state mutations.

## Calendar data layer gotchas
- `lift.sessions` has **`started_at`** (not `created_at`) and `completed_at`. Selecting `created_at` causes a silent 400 from Supabase and returns `[]`.
- Do **not** chain `.not('completed_at', 'is', null)` with `.gte`/`.lte` on the same column — PostgREST returns 400. The range filters already exclude NULLs.
- PWA on iOS caches aggressively — service worker may serve stale `index.html` until the next cold launch. Expect a lag between GitHub Pages deploy and the phone reflecting changes.

---

## UI Redesign Guardrails

This section exists so a UI overhaul cannot silently break clinical logic. It separates **load-bearing interactions** (changing their trigger conditions or removing them would break the clinical state machine, even if their visual presentation changes freely) from **cosmetic elements** (safe to restyle with zero clinical risk).

A redesign can change how something looks or how the user reaches it; it cannot remove or defer the underlying function call.

---

### Load-bearing interactions — preserve trigger conditions

**Morning check-in (pain scale + swelling toggle)**
Call chain: `saveCheckin()` → `saveDailyLog(painLevel, jointFullness)` + `evaluateFlare(painLevel, jointFullness)`
- The specific pain integer (`knee_pain_level`, 1–5) and swelling boolean (`joint_fullness`) are the direct inputs to the flare/deload/regression state machine. A redesign can use a slider, big buttons, a number pad — anything — but must still capture exactly these two values and pass them to both functions on every submit.
- `evaluateFlare` must be called on the same submit, not deferred to the next app boot. Splitting check-in into two separate screens (pain today, swelling tomorrow) would break the deload trigger.
- Wording of pain labels (e.g. "No pain" / "Mild" / "Severe") is safe to change as long as the underlying integer submitted to the DB does not change.

**Run/rehab completion toggles**
Call chain: `toggleRun()` / `logAlternateActivity(type)` / `toggleRehab()` / `rehabMarkComplete()` → each must call `maybeWriteCycleDayAdvance()` after writing to the DB.
- `maybeWriteCycleDayAdvance()` is the entire cycle-advance trigger — it writes `lift_cycle_day_pending` to localStorage, which `loadBootData` applies the next morning. If this call is dropped from any of the four entry points, the rehab cycle cursor stalls silently and permanently.
- Redesigning these as checkboxes, swipe gestures, confirmation dialogs, or different components is safe as long as the underlying function is still called after the DB write.
- `logAlternateActivity` is the path for alternate-activity logging on *run days* (sets `run_completed = true`). `logCrossTraining` is for *non-run days* (sets `cross_training_completed = true` only). Do NOT swap these paths — `logCrossTraining` does not call `maybeWriteCycleDayAdvance` by design.

**Skip-reason capture (`'niggle'` / `'travel_equipment'` / `'other'`)**
Call chain: `doSkipSet(reason)` / `skipWholeExercise(idx, reason)` → conditional `markNiggleFlare()`
- The exact string values are not cosmetic. `'niggle'` is the key that triggers `markNiggleFlare()` (marks cycle dirty, resets ROM clock), subject to the run+lift-day knee-loading exemption (`isRunAndLiftDay() && isKneeLoading(ex)`). `'travel_equipment'` and `'other'` do not call `markNiggleFlare`.
- A redesign can restyle the skip picker (bottom sheet, inline buttons, icons, different label copy) but must pass these exact string values through to the underlying functions. Renaming `'niggle'` to `'pain'` or `'injury'` without updating the gate check in `doSkipSet` and `skipWholeExercise` would silently break the flare logic.

**"Confirm progression" toggle (`APP.progressionReady`)**
- All weight advances are gated on `APP.progressionReady = true`, which can only be set by an explicit user action on set 3. The engine does not auto-advance based on rep counts alone.
- A redesign must NOT merge "log reps" and "confirm progression" into a single action. The opt-in confirmation is a deliberate safety gate — auto-advancing weight based on rep achievement alone would bypass the user's judgment about form quality and readiness.
- The confirmation button appearing (and its label from `progressionHint()`) is conditional on the progression engine computing a pending advance. Do not hard-code the button to always appear.

**Run-outcome picker (Clean / Flagged)**
Call chain: `saveRunOutcome('flagged')` → `applyFlareConsequences()` → `refreshReadiness()`
- A `'flagged'` run must trigger **immediate** flare evaluation, not deferred to the next check-in. `saveRunOutcome` calls `applyFlareConsequences()` directly, which writes the deload/regression patch to `plan_state` in the same session.
- A redesign can change the picker's appearance (thumbs up/down, emoji, Clean/Flagged buttons, a post-run form) but must preserve this immediate call path. If flagged-run processing is deferred to the next morning's check-in, the deload does not take effect until then — the user could continue loading the knee in the same session.
- Un-logging a run (`toggleRun()` setting `run_completed = false`) also clears `run_outcome = null` — this pairing must be preserved.

**Long-press state-editor panel (the manual-correction path)**
Trigger: 600 ms long-press on `#phase-badge` via `badgePressStart` / `badgePressEnd`
- This is the **only** non-DB manual-correction path into `plan_state`. If a redesign removes or re-routes the long-press, the cursor-editing capability must be preserved somewhere else.
- The entry mechanism can change (different gesture, hidden developer menu, settings screen behind N taps). But it must remain **intentional and non-accidental** — NOT a plain visible button or inline toggle, because accidental taps would silently mutate the clinical cursor (`current_phase`, `current_cycle_day`, `current_gym_day`).
- The `stateMarkLiftDone` / `stateMarkLiftNotDone` lift-history toggles and the session re-date/delete functions inside this panel are also the only correction paths for lift history without direct DB access. Preserve them if the panel is redesigned.

**Wake lock / timer screens**
Control point: `if (aTimerIsRunning()) requestWakeLock(); else releaseWakeLock();` at the end of every `render()`.
- `aTimerIsRunning()` currently checks `APP.timerActive` (rest timer), `APP.rehabTimerActive` (rehab set timer), and `APP.rehabRestActive` (rehab inter-set rest). If new screens are added that display a countdown (e.g. a warm-up timer, a cool-down screen), `aTimerIsRunning()` must be updated to include those states, or the wake lock will release mid-timer and the chime will silently fail on iOS.
- The check lives at the end of `render()`, which runs after every state change. Keep it there. Do not move it into individual screen render functions — the centralised check is what guarantees the lock releases correctly even after `skipWholeExercise`, navigation, or an unexpected screen transition.

**Buffer-day and ad-hoc-lift-card visibility conditions**
Variables: `APP.isBufferDay`, `APP.todayPlan.is_lift_day`
- `APP.isBufferDay = true` suppresses the run card entirely (prevents logging `run_completed = true` when the cycle cursor is not in a state to process it) and shows the buffer-day lift card instead of the scheduled lift card.
- `is_lift_day` determines whether the scheduled lift card, the buffer-day card, or the ad-hoc (optional) lift card renders. These are gate conditions, not presentation choices.
- A redesign can change the visual treatment of each card freely. It must not unify the three card types into a single unconditional component that ignores these flags — the different cards have different underlying call paths (e.g. `startWorkout()` with vs. without the buffer-day context).

---

### Safe to change freely (zero clinical coupling)

The following are purely presentational and carry no risk to the clinical state machine:

- **Color tokens** (`--color-*`) and dark/light theme definitions.
- **Border radius** (`--radius-*`), card shapes, shadows, borders.
- **Icons** (Tabler webfont `ti-*` classes) — swap any icon for any other.
- **Copy / wording** in banners, card labels, and button text — including pain button labels (1–5), as long as the integer submitted does not change.
- **Animations** — transition durations, loading spinners, entrance/exit effects.
- **Typography** — font families, sizes, weights, line heights.
- **Layout and spacing** — card order on the today screen, padding, max-width.
- **Deload banner and readiness badge** visual treatment — their render *conditions* (`ps.in_deload`, `APP.readiness`) must stay; their visual design (color, icon, placement, copy) is free.
- **Rest timer display** (the countdown digits, any progress arc, the Skip button placement) — can be fully redesigned as long as the `setInterval` arm/disarm in `render()` and the wake-lock logic at the bottom of `render()` remain intact.
- **Rehab card layout** on the today screen and the rehab exercise detail screen — freely redesignable; the underlying `toggleRehab()` / `rehabMarkComplete()` call chain must remain.
