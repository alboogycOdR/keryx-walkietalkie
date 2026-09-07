# TASK-046 — RadioViewState presentation projection + telemetry honesty

## Brief

A pure projection between TASK-045's host and every successor screen, so no
widget reads raw reducer state or invents its own state machine. Phase,
emergency, latch, denied flash, connection condition and service/permission
faults are modelled as *independent* fields with deliberate precedence — not a
single priority switch. Telemetry honesty ships with it: placeholder quality and
unknown LINKED roster counts project as unavailable, and any level animation is
typed as decorative.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §5.1 (command path; the UI
  never synthesizes floor events), §5.2 (composite state), §5.3 (telemetry
  honesty), §1.1 (`StationInfo.signalQuality` placeholder max; the mislabelled
  amplitude meter "must not migrate"; the `RadioState` equality gap), §9.
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §4 — the 13-row state
  catalogue and the "emergency is an overlay, not a replacement" rule.
- PRD UX-FR-002/022/026/027/045/046; Verification VT-010, VT-015, VT-024.
- ADR-001 §5/§6 — reducer and floor semantics are not superseded.

## Approach

Immutable view-state + typed intents in `lib/core/presentation/**`, delegating
every intent to the host. Model both `measured` and `unavailable` telemetry
variants so TASK-065's real RX source can plug in later without a redesign —
but do not depend on TASK-065 landing. Assess Technical §1.1's `RadioState`
equality gap against each projected field and report rather than "fix" the
reducer; a genuine dependency on an excluded field is a `SPEC_AMBIGUITY` block,
not an opportunistic reducer change.

## Work Log

- [2026-09-07T19:11Z] [S5] Claimed. Preflight (`python scripts/preflight_paths.py TASK-046`):
  ```
  [preflight] TASK-046 Owned_Paths inspected in E:/DELL-PROJECTS/wt-s5-WALKIETALKIE
  [preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
    GLOB   lib/core/presentation/**  -> matches nothing yet (new territory)
    GLOB   test/core/presentation/**  -> matches nothing yet (new territory)
    FILE   dossiers/TASK-046.md  -> exists, 34 line(s), 1758 bytes
  [preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
  ```
  Read TASK-045's `RadioHostContract`/`RadioHostSnapshot`, `RadioState`/`RadioReducer`, `RadioSessionController`'s `_resolveEffectiveMode`, `KeryxSettings`, `StationInfo`, and all five Mobile UX Redesign specs in full before writing code.

- [2026-09-07T19:11Z] [S5] **Written RadioState equality-gap assessment (acceptance criterion 9; Technical §1.1: "The existing state machine has a known equality concern: its value equality does not include every state field").** Audited `lib/core/state/radio_state.dart` field-by-field: `RadioState` declares exactly 17 final fields (phase, mode, channel, privacyCode, isNoLink, isEmergency, isPrivate, isReplay, isMonitorOpen, isScanning, isVoxArmed, isTotWarning, isTransmitDenied, stationCount, activeSpeaker, arbiterId, signalQuality). Its `operator ==` and `hashCode` both enumerate all 17 of the same fields — **no field is currently excluded**. Locked in as an executable regression guard in `test/core/presentation/radio_view_state_test.dart` (group "Technical §1.1 — RadioState equality-gap assessment"): a base instance is copied with exactly one field flipped at a time, for all 17 fields, and each variant is asserted unequal to the base. If a future edit to `radio_state.dart` reintroduces an excluded field, this test fails immediately, naming the class where the gap would reopen.
  **Conclusion: no projected field in this task's `RadioViewState` depends on an excluded `RadioState` field, because none is currently excluded.** No `SPEC_AMBIGUITY` block needed. Filed as a non-blocking finding for ORCH rather than silently ignored: the spec text (baseline commit `55c51da2`) describes a gap that does not match the current code at this task's baseline — either it was already closed by an earlier task without the spec being updated, or the spec's authors were describing a different/earlier revision. Recommend ORCH confirm and, if so, note the closure in the spec's own changelog so the next reader isn't sent looking for a gap that isn't there. **Per Technical §1.1's own instruction, reducer semantics were NOT changed to "fix" this — there was nothing to fix.**

- [2026-09-07T19:11Z] [S5] Implemented `lib/core/presentation/**`: `presentation_cue.dart` (framework-agnostic label/iconId pair, no `IconData`/`BuildContext` — keeps this layer Flutter-widget-free and colour as the theme layer's job per Design §3.2), `telemetry.dart` (`SignalQuality`/`RosterCount`/`MeterLevel` sealed unions, each with an `unavailable`/`decorative` variant used today and a `measured` variant reserved for KRX-035/TASK-065), `connection_condition.dart` (configured mode vs effective route vs degraded, kept independent per UX-FR-002/Technical §7), `tuning_target.dart` (requested-vs-authoritative tune target, Technical §6), `radio_phase_presentation.dart` (an extension mapping each of the 8 `RadioPhase` values to its Design §4 catalogue cue), `radio_view_state.dart` (the `RadioViewState` immutable projection + `OverlayCues` for the 5 non-phase catalogue rows + `RadioViewState.project` pure factory), `radio_view_intents.dart` (`RadioViewIntents`, pure delegation to `RadioHost` for press/release/latch-release/tune/apply-settings/join-event), `presentation.dart` (barrel export).
  Roster-count rule in `project()`: `RadioSessionController` only wires LOCAL discovery's `SignalingService` into the station stream (`_adoptEngine(engine, signaling: signaling)` for LOCAL, `signaling: null` for LINKED) — so under the current codebase a LINKED session's station stream is always empty, never a real roster. `project()` therefore reports `KnownRosterCount` only when `RadioState.mode == RadioMode.local`; every other effective route reports `UnavailableRosterCount`, even if `hostSnapshot.stations` happens to be empty (never a false "verified zero").
  Signal quality is unconditionally `SignalQuality.unavailable` — confirmed via grep that `RadioStateBridge.updateSignalQuality` (the only path that could feed `RadioState.signalQuality` a real value) has zero production callers, and `StationInfo.signalQuality` is TASK-035's disclosed placeholder maximum. Meter level is unconditionally `MeterLevel.decorative` — no real audio-tap source exists yet (reserved for TASK-065).
  `activeOverlayCues`/`receivingLabel` are additive composition helpers, not a collapsing "primary state" switch — Technical §5.2 forbids a single priority switch, so no such switch was written; a consuming screen reads `phaseCue` (1 of 8) plus zero-or-more `activeOverlayCues` (0–5) plus `receivingLabel` and composes its own layout.

- [2026-09-07T19:11Z] [S5] Tests: `test/core/presentation/radio_view_state_test.dart` (25 cases) + `radio_view_intents_test.dart` (7 cases), all against acceptance criteria 1–9 by name in each test's own description. `flutter analyze lib/core/presentation test/core/presentation` — clean. Full suite: 1096 passed, 0 failed, 40 skipped (unchanged parked FR-025 seeds) — `flutter test`. No pre-existing failures introduced; the only remaining `flutter analyze` warnings repo-wide are the 8 pre-existing `test/services/session/radio_session_controller_test.dart` warnings already disclosed as TASK-035 debt, untouched by this task.

- [2026-09-07T19:15Z] [S5] **Revert-mutation-checked 4 of the new regression tests before resubmission (standing dispatch rule from TASK-037's review), each in an isolated scratch edit reverted immediately after, never committed:**
  1. `radio_state.dart`'s `==` — stripped `stationCount == other.stationCount &&` (scratch-only, not committed; `lib/core/state/**` is outside this task's `Owned_Paths`) → the equality-gap regression test (`test/core/presentation/radio_view_state_test.dart`, "Technical §1.1") failed exactly as designed, reporting the two mismatched instances by name. Restored byte-identical (`git diff` empty after).
  2. `radio_view_state.dart`'s roster rule — changed `radioState.mode == RadioMode.local` to a bare `true` → the "unknown/incomplete LINKED roster … never a verified zero count" test failed (`Expected: UnavailableRosterCount, Actual: KnownRosterCount(0)`). Reverted; `git diff` empty after.
  3. `radio_view_intents.dart`'s `press()` — changed to call `_host.releasePtt()` instead of `_host.pressPtt()` → the "press() forwards to RadioHost.pressPtt exactly once" test failed (`Actual: ['releasePtt']`). Reverted; `git diff` empty after.
  Each mutation bit exactly the one test it targets; no other test in the suite moved. `flutter analyze` clean and full suite 1096/0/40 reconfirmed after every revert.
  → `Status: needs_review`.
