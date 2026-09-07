# TASK-059 — Physical-device LOCAL acceptance

## Brief

The first hardware gate, carrying double duty: it validates the successor shell
and finally confirms or refutes TASK-044's Android audio-session/routing fix,
which has never run on a phone. The 2026-08-23 field test found discovery working
and no voice flowing; this is where that is settled.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` §7 (the real-device
  matrix and its LOCAL rows; "Do not claim a release candidate is audio-verified
  based only on emulator, fake adapter or compile success"), §9 gate G5, §0.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §0, §12 (unverified routing
  correction; review remote-track handling if voice remains absent).
- PRD §7 (bidirectional voice on two real devices); ADR-001 §5.
- `ops/TWO_PHONE_TEST.md` — the existing runbook this test builds on.

## Approach

Two physical Android devices, different manufacturers where possible; record
model, OS, commit, network config and per-row result in `ops/FIELD_TEST_LOCAL.md`.
A failed row is recorded as failed with a recommended successor task — never
converted to a pass by assumption. If voice is still absent, the documented next
step is TASK-065's remote-track handling, not blaming the new UI.

## Work Log
