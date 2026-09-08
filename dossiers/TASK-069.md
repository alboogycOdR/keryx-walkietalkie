# TASK-069 — Keyboard/switch access for Radio Controls' hold targets

## Brief

ORCH-created 2026-09-08, an accepted-not-fixed finding from TASK-057's
review: Monitor's hold-to-open and Emergency's 600ms hold-to-arm are both
pointer-only gestures with no keyboard/switch equivalent. This needs its own
explicit decision — not a copy of Talk's latch-release button — because
Emergency's accidental-activation guard must not be weakened by whatever
keyboard analog is chosen.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §5 — functional floor
  (names TX-latch release explicitly, silent on Monitor/Emergency
  specifically — this task fills that silence with a documented decision).
- TASK-057's Review_Findings — the accepted finding this task closes.
- TASK-054's existing pointer-based Emergency tests (600ms hold, early-release
  safety) — must stay green, unchanged, for pointer input.

## Intended approach

1. Decide and document (before writing code) how a keyboard/switch user
   activates a hold-gated control safely — e.g. a distinct
   confirm-then-arm two-step, or an explicit "hold substitute" action —
   without making Emergency easier to trigger by accident than the pointer
   path.
2. Implement for both Monitor and Emergency.
3. Regression test: keyboard/switch activation works; existing pointer
   semantics (600ms hold, early-release-cancels) are unchanged.
4. Full suite + analyze; revert-mutation the new tests.

## Work Log
