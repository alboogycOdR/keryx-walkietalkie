# TASK-107 — Host re-adopts the floor engine after switchTarget

## Problem

`KeryxRadioHost` captures `session.floorEngine` once in `_startSession`.
`RadioSessionController.switchTarget` tears that engine down and adopts a
new one. PTT, effects, meter and `RadioHostSnapshot.floorEngine` stay on
the disposed boot engine — the journey harness had to swallow
`releaseTransmit` throwing from `host.dispose()`.

## Shape

1. `SessionHost.engineChanges` (default empty stream so out-of-territory
   fakes compile) implemented by `RadioSessionController` and passed
   through `RadioSessionHostAdapter`.
2. Host re-adopts on every emission with `_disposed` / generation /
   session-identity guards matching `_startSession`.
3. `_teardownActive` releases in-flight local TX before disposing the
   engine, while `RadioStateBridge` is still subscribed.
4. Journey harness drop the throw-swallow; new gate: PTT after select.

## Work Log

- [2026-09-13T07:12:00Z] [GB] Claimed. Preflight pasted in PLAN.md.
  Implementing.
- [2026-09-13T07:29:00Z] [GB] Done. `SessionHostEngineEvents` opt-in (not a
  `SessionHost` member — `implements` fakes outside territory would not
  compile). Controller emits sync `engineChanges` on `_adoptEngine`;
  `_teardownActive` `releaseTransmit`s first; host re-adopts with
  generation/`_disposed`/session-identity guards. Journey throw-swallow
  removed; PTT-after-select gate green. Mutation: omit `_engineChanges.add`
  → switch_target tests red + dispose throws the original defect; restored.
  Full suite +1490 ~43 -0. Analyze: unused import fixed, files clean.
