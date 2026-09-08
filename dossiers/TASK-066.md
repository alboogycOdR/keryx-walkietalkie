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
