# TASK-050 — Channel selector and tune coordinator

## Brief

The selector UI plus the retune serialization work Technical §6 explicitly names
as a dedicated migration task: today the app dispatches `TuneTo` and fires an
async retune without awaiting it, so competing requests race. Deliver direct
entry and list selection (1–99 / 0–38, two-digit labels, recall as a separate
section, Apply disabled while invalid, Cancel a true no-op) over a coordinator
with a deterministic latest-wins policy.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.3 — full selector contract,
  pending-retune progress, "currently active channel remains authoritative".
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §6 — latest-wins, no
  optimistic claims, and "do not invent rollback support" where the previous
  chain is already torn down: document and test a recovery policy instead.
- PRD UX-FR-003/004/009/010/030; Verification VT-020, VT-021.
- ADR-001 §5 — session retune contracts preserved; the fix is at the coordinator.

## Approach

Build over TASK-045's single serialized tune entry point. Keep the requested
target visibly distinct from the authoritative current channel while tuning.
VT-021's deferred-future ordering test is the load-bearing evidence — write it
first, then make it pass.

## Work Log

- [2026-09-08T13:45:00Z] [S5] Claimed and implemented in one session on branch
  `task/TASK-050-s5`. Preflight (`python scripts/preflight_paths.py TASK-050`):
  both `lib/features/channel_selector/**` and `test/features/channel_selector/**`
  were `GLOB -> matches nothing yet (new territory)`; `dossiers/TASK-050.md`
  existed (this file). Discovered `RadioHost.tune` already serializes
  competing calls at the host (`_tuneChain` in `keryx_radio_host.dart`,
  TASK-045's own territory) and `RadioViewState.pendingTuningTarget` /
  `TuningTarget` already exist from TASK-046, explicitly caller-supplied
  ("whichever component actually tracks a tune request's lifecycle") — so
  this task's real job was the UI-side lifecycle tracker
  (`TuneCoordinator`) plus the screen itself, not re-implementing host
  serialization. Built `channel_validation.dart` (pure parsing),
  `tune_coordinator.dart` (pendingTarget tracking, TX-deferral for
  UX-FR-030, recovery-policy classification, a generation guard against
  out-of-order host responses for VT-021's "no stale state adoption"),
  `channel_selector_screen.dart` (Design §2.3 direct entry + TASK-049's
  existing `visibleChannelMemory`/`formatChannelCode` for the recall
  section — reused, not reimplemented). 27 new tests across 3 test files
  (5 validation + 10 coordinator unit + 12 screen widget), all passing.
  `flutter analyze` clean repo-wide (only the 8 pre-existing TASK-035
  warnings). Full suite: 1227 passed / 0 failed / 40 skipped. `flutter
  build apk --debug` succeeded. Revert-mutation-checked 3 load-bearing
  guards (generation staleness guard, TX-deferral gate, screen's
  canApply busy guard) — each flip failed exactly its own targeting
  tests, nothing else, all reverted clean. Reverted the standing
  local-toolchain auto-edits (analysis_options.yaml,
  android/gradle.properties) before every commit. All 10 acceptance
  criteria checked; the "ordinary navigation does not interrupt TX" and
  "cosmetic labels" clauses are satisfied by construction (this screen
  never calls pressPtt/releasePtt/releaseLatch and never introduces a
  cosmetic-name layer) rather than by a dedicated test — noted inline on
  the PLAN.md criterion and in Test_Evidence. -> Status: needs_review.
