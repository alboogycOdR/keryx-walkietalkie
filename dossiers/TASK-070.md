# TASK-070 — Lock in channel/privacy-code boundary validation

## Brief

ORCH-created 2026-09-09, a routed finding from TASK-058's round-2 review:
VT-020 requires boundary coverage for channel (1-99) and privacy-code (0-38)
input, but only `tune(0,0)` was ever exercised — the actual edges were
never tested. ORCH read `channel_validation.dart` directly before creating
this task: the logic already appears correct (regex rejects negatives
outright, range check handles the rest). No defect is assumed — add the
tests, confirm the logic really holds at every edge, fix narrowly if not.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` VT-020.
- `specs/KERYX_Mobile_UX_Redesign_PRD_v1.0.md` UX-FR-003.
- TASK-058's Review_Findings §9.9 — the exact gap this closes.
- `lib/features/channel_selector/channel_validation.dart` — read it before
  writing tests; don't guess at the boundary semantics.

## Intended approach

1. Add explicit test cases: channel 1/99 (valid), 0/100 (invalid); code
   0/38 (valid), "-1"/39 (invalid, and confirm "-1" is rejected as
   non-digit text, not parsed as a negative int).
2. If every case passes against the existing implementation, that's the
   whole task — the logic was already correct, now it's proven.
3. If a real boundary bug surfaces, fix it narrowly in
   `channel_validation.dart` only, document exactly what was wrong.
4. Revert-mutation the new tests; full suite + analyze.

## Work Log
