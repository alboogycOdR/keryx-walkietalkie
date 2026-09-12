# TASK-097 — Radio boot must not hang forever when session start stalls

**Unit:** S5 | **Branch:** task/TASK-097-s5

## Problem (owner field report 2026-09-12)

PTT stuck on "Starting radio" indefinitely with "This network only" ON and
"Active path: Connecting" never resolving. Traced live to two unbounded
`await` chains with no timeout anywhere upstream:

- `KeryxRadioHost._bootInternal` -> `_startSession` -> `await session.start();`
- `RadioSessionController.start()` -> `_startLocal()`/`_startLinked()`, each a
  plain sequential `await` chain (`signaling.start`/`discovery.start`/
  `discovery.onTuned()` for LOCAL; `linked.joinRoomId(...)` for LINKED).

Any one of these suspending forever (no reachable LAN peer with local-only
forced, an unreachable relay, a hung platform `MethodChannel` call) left
`BootCompleted` never dispatched, `RadioPhase` stuck in `boot` forever, no
error surfaced, no way to recover short of a restart.

## Design

Two-layer bound, both new/injectable `Duration` fields with production
defaults (controller 20s, host 25s — the controller's own bound normally
fires first in production, giving the more specific transport-labelled
reason; the host's outer bound is a defense-in-depth net for any
`SessionHost` implementation that does not self-bound):

1. **`RadioSessionController._startLocal`/`_startLinked`** — every risky
   `await` wrapped in `.timeout(_sessionStartTimeout)`; a catch-all around
   each method's body converts a timeout *or* any real thrown failure into a
   new typed `SessionEstablishmentFailure(transport, cause, stackTrace)`,
   best-effort disposing whatever was already constructed in that scope
   first (signaling/discovery for LOCAL; linked/proxyTransport/engine for
   LINKED). Wrapping the whole method (not just `start()`'s call site) means
   `switchTarget()` — which calls the same two private methods — gets the
   same bound for free; a dedicated test proves it.

2. **`KeryxRadioHost._startSession`** — `await session.start()` gets its own
   outer `.timeout()` + catch-all, independent of whatever the concrete
   `SessionHost` does internally (verified directly with a hand-written
   `_HangingSessionHost` test double, not a real `RadioSessionController`).
   On any failure: logs, best-effort disposes the failed session, records a
   new `SessionFailureKind` (`local`/`linked`) on `RadioHostSnapshot`, still
   dispatches `BootCompleted` (unless mic denied — untouched, separate
   failure mode) so the phase actually leaves `boot`. `floorEngine`/`_session`
   were already left `null` by the pre-existing teardown-before-attempt code
   at the top of `_startSession`, so PTT staying disabled falls out for free
   (`talk_screen.dart`'s `ptteEnabled` already gates on
   `_snapshot.floorEngine != null` — verified, not touched, out of
   Owned_Paths anyway).

   Which transport the host names is resolved **independently of the thrown
   exception's own `transport` field**, straight from the `KeryxSettings`
   snapshot (`_intendedFailureKind`, mirroring
   `RadioSessionController._resolveTransport()`'s exact pure classification)
   — this is what lets the *same* code path work uniformly whether the
   failure came from a real `RadioSessionController`'s typed exception or a
   bare `SessionHost` test double that just times out.

3. **Presentation** — `RadioHostSnapshot.sessionFailureKind` (new enum
   `SessionFailureKind { local, linked }`) projects through
   `RadioViewState.sessionFailureKind` into two new static `OverlayCues`
   (`localSessionFailed` = "Couldn't find anyone nearby",
   `linkedSessionFailed` = "Couldn't reach the relay") added to
   `activeOverlayCues`. Deliberately **not** a new `RadioPhase` — the
   Description explicitly asked to "reuse or extend the existing
   overlay-cue mechanism ... rather than silently falling through to a
   happy-path idle", and the class's own dartdoc says `RadioPhase` "remains
   unchanged unless a separately approved defect requires a reducer
   change". Falling through to `idle` is not "silent" here because the new
   overlay cue is what makes it honest.

4. **Recovery gap found and fixed while implementing:**
   `KeryxRadioHost._maybeRebuildSession`'s original guard
   (`applied == null` -> "still booting, skip") would have made a failed
   session **permanently unrecoverable** — `_appliedSettings` only gets set
   on the success path, so after a failure it would stay `null` forever,
   and no later settings change (relay reachable again, `forceLocalOnly`
   flipped off) could ever trigger a retry. Fixed by also treating
   `_sessionFailureKind != null` as "an attempt has concluded" in that
   guard. This does not change behavior for the pre-existing
   never-failed case (both fields stay `null` during the genuine
   still-booting race the original guard was protecting) — a dedicated
   test proves recovery now works.

## Disclosed limitation (accepted, not fixed)

`.timeout()` stops *awaiting* the underlying call; it does not cancel it. A
genuinely hung native platform call (NSD registration, a wedged relay
connect) may keep running in the background after this bound has already
surfaced a failure to the UI. Cancelling it would need a cancellation seam
inside `NsdDiscoveryService`/`SignalingService`/`LinkedController`/
`LiveKitAdapter` — all outside this task's `Owned_Paths` (frozen since
TASK-094). The bound here is a UI-facing guarantee ("never stuck showing
boot forever"), not a resource-cleanup guarantee for an uncancellable
platform call. Documented inline at both `_startLocal`/`_startLinked`'s
dartdoc.

## Files touched

- `lib/core/radio_host/radio_host_snapshot.dart` — `SessionFailureKind` enum,
  `RadioHostSnapshot.sessionFailureKind` field.
- `lib/core/radio_host/keryx_radio_host.dart` — outer bound in
  `_startSession`, `_intendedFailureKind`, `_maybeRebuildSession` recovery
  fix, `sessionStartTimeout` constructor param.
- `lib/services/session/radio_session_controller.dart` —
  `SessionEstablishmentFailure`, bounded/cleaned-up `_startLocal`/
  `_startLinked`, `sessionStartTimeout` constructor param.
- `lib/core/presentation/radio_view_state.dart` — two new `OverlayCues`,
  `RadioViewState.sessionFailureKind`, `activeOverlayCues` wiring.
- Tests: `test/services/session/radio_session_controller_test.dart`,
  `test/core/radio_host/keryx_radio_host_test.dart`,
  `test/core/presentation/radio_view_state_test.dart`.

Not touched: `lib/core/state/radio_state.dart` (no new `RadioPhase`),
`lib/core/presentation/radio_phase_presentation.dart` (no new phase to map),
`lib/features/talk/talk_screen.dart` (out of Owned_Paths; verified its
`ptteEnabled` gate already covers this state via `floorEngine != null`,
per the task Description's own note).

## Work Log

- [2026-09-12T15:00:00Z] [S5] Claimed, preflight passed, read the two
  implicated source files in full plus every dependency (`session_host.dart`,
  `radio_host_snapshot.dart`, `radio_view_state.dart`,
  `radio_phase_presentation.dart`, `radio_state.dart`, `discovery_service.dart`,
  `linked_controller.dart`, `livekit_adapter.dart`, `token_client.dart`)
  before writing any code. Designed the two-layer bound + presentation
  wiring above.
- [2026-09-12T15:20:00Z] [S5] Implemented all four production-file changes.
  `flutter analyze --no-pub lib/ test/` -> No issues found.
- [2026-09-12T15:30:00Z] [S5] Added and ran targeted tests: 4 new tests in
  `radio_session_controller_test.dart` (LOCAL timeout, LOCAL thrown failure,
  LINKED timeout, switchTarget shares the bound) — all pass, full file
  28/28. 5 new tests in `keryx_radio_host_test.dart` (timeout->BootCompleted,
  LINKED naming, PTT-inert, mic-denied-unaffected, recovery-clears) — all
  pass, full file 15/15. 4 new tests in `radio_view_state_test.dart`
  (local/linked cue distinctness, no-failure baseline, phase-independence)
  — all pass, full file 59/59 (combined with the controller file in one run).
- [2026-09-12T15:40:00Z] [S5] Found and fixed the `_maybeRebuildSession`
  permanent-lockout gap while writing the recovery test (see Design §4
  above) — in scope, in territory, required for the fix to actually be
  useful rather than trading "stuck in boot" for "stuck in a failure state
  no retry can ever clear".
- [2026-09-12T15:45:00Z] [S5] `flutter analyze --no-pub lib/ test/` (repo-wide)
  -> No issues found. Full `flutter test` run launched; evidence appended to
  PLAN.md Test_Evidence once complete.
