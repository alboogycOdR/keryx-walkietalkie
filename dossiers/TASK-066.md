# TASK-066 — Project TOT warning into RadioViewState

## Brief

ORCH-created 2026-09-08, a narrow carve-out from TASK-051's round-2 review:
Talk needed to surface the TOT (time-out-tension) warning but `RadioViewState`
has no field for it, and Talk correctly refused to bypass its own
presentation boundary to read `RadioState.isTotWarning` directly. Add exactly
one independent field to `RadioViewState`, following TASK-046's established
pattern — do not touch `lib/features/talk/**`.

## Spec pointers

- `specs/KERYX_Product_Technical_Spec_v1.1.md` FR-023 — TOT semantics.
- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §4 — "TX time-out warning"
  catalogue row.
- TASK-046's `RadioViewState`/`RadioViewIntents` (`lib/core/presentation/**`)
  — the exact pattern to extend: independent fields, host-snapshot-sourced,
  zero reducer changes.
- TASK-051's Review_Findings (round 2) — the carve-out request itself.

## Intended approach

1. Read `RadioState.isTotWarning` (or equivalent) in `lib/core/state/`.
2. Add one field to `RadioViewState`'s projection, sourced the same way every
   other field already is (via the host snapshot, not a new subscription).
3. One test proving TOT-warning and TX-granted project simultaneously
   (independent-fields pattern), mirroring the existing emergency-during-TX
   test.
4. Full suite + analyze; leave Talk-side wiring to a follow-up.

## Work Log

- [2026-09-08T11:15:00Z] [GB] Claimed. No in_progress/claimed GB task at session start. Preflight:

```
[preflight] TASK-066 Owned_Paths inspected in E:/DELL-PROJECTS/wt-grok-WALKIETALKIE
[preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  GLOB   lib/core/presentation/**  -> 8 file(s):
           lib/core/presentation/connection_condition.dart
           lib/core/presentation/presentation.dart
           lib/core/presentation/presentation_cue.dart
           lib/core/presentation/radio_phase_presentation.dart
           lib/core/presentation/radio_view_intents.dart
           lib/core/presentation/radio_view_state.dart
           lib/core/presentation/telemetry.dart
           lib/core/presentation/tuning_target.dart
  GLOB   test/core/presentation/**  -> 2 file(s):
           test/core/presentation/radio_view_intents_test.dart
           test/core/presentation/radio_view_state_test.dart
  FILE   dossiers/TASK-066.md  -> exists, 32 line(s), 1444 bytes
[preflight] Paste this output into your first Progress_Note as the c8b9872 filesystem check.
```

- [2026-09-08T11:18:00Z] [GB] **Design §4 citation vs table.** Spec_References name a Design §4 "TX time-out warning" catalogue row. The live Design §4 table (13 rows) has no such row; TX granted's treatment is "Red + timer if authoritative". The named state is DS §6 / FR-023. Not blocked: field semantics are fully specified (independent bool, sourced from `RadioState.isTotWarning`, text+icon cue not colour-only). **Pinned cue copy:** label `Transmission ending soon` (Design §5 plain language; FR-023 T-5 s), iconId `timer` (unused by the 13 Design §4 cues). Direct constructor default `totWarning = false` so out-of-territory `RadioViewState(...)` call sites (stations/settings tests) keep compiling; `project()` always passes `radioState.isTotWarning`. No `lib/core/state/**` or `lib/features/talk/**` edits. Talk already iterates `activeOverlayCues`, so the chip will appear without a Talk edit; its `_iconForCueId` falls through unknown ids to `Icons.circle` until a Talk follow-up maps `timer`.

- [2026-09-08T11:20:00Z] [GB] Landed `RadioViewState.totWarning` + `OverlayCues.totWarning`. `project()` copies `radioState.isTotWarning` (same seam as `emergency: radioState.isEmergency`). `activeOverlayCues` includes the TOT cue after Denied/busy, before Latched. Three new tests: TX+TOT independent fields; totWarning not fabricated from phase==tx; cue text+icon distinct from Design §4's 13 labels.

- [2026-09-08T11:21:00Z] [GB] Revert-mutation (restored after each, `git diff` of the mutated line empty after):
  1. `totWarning: false` (ignore `isTotWarning`) → TOT-during-TX test red: Expected true, Actual false.
  2. `totWarning: true` (fabricate) → sourced-from-RadioState test red: Expected false, Actual true.
  3. omit `if (totWarning) OverlayCues.totWarning` → TOT-during-TX test red: Expected contains PresentationCue(Transmission ending soon, icon: timer), Actual [].
  Each mutation flipped only its target assertion.

- [2026-09-08T11:22:00Z] [GB] Tests: `flutter test test/core/presentation/` 29/29. `flutter analyze lib/core/presentation test/core/presentation` No issues found. Repo-wide analyze: 8 pre-existing TASK-035 warnings in `radio_session_controller_test.dart` only. `flutter test` **1290 passed / 0 failed / 40 skipped** (parked FR-025 seeds unchanged). `git diff -- lib/core/state/` empty. Analyzer auto-upgrade of `analysis_options.yaml` reverted, not committed. → needs_review.

