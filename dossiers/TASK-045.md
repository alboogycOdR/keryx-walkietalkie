# TASK-045 — Persistent RadioHost extraction

## Brief

Everything in this wave depends on this task. `_FaceScreenState` currently
constructs and disposes the entire radio stack — `SessionHost`/
`RadioSessionController`, the floor engine, `AudioSink`, `SfxEngine`,
`SfxProjection`, `RadioServiceController` and the station notifier — inside
`initState`→`_boot()`/`dispose()`. Any disposable route above that widget kills
the session on navigation, so an app-scoped host must exist before a navigation
shell can. This is a hoist, not a rewrite: no new engine, session, transport or
audio pipeline is created.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §1.1 (the exact ownership
  inventory and why FaceScreen-under-a-route is wrong), §2 (target architecture),
  §3 (illustrative `RadioHost` contract + typed results), §4 (ten lifecycle
  invariants), §9 (`lib/core/radio_host/`, and "a separate integration task owns
  app.dart / route registration" — that is TASK-048, not this one).
- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` VT-001 (single instance),
  VT-002 (boot race), VT-003, VT-004 (disposal/background).
- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §6 — the migration
  diagram; the host box is explicitly "hoisted out, unchanged in substance".
- `specs/KERYX_Product_Technical_Spec_v1.1.md` §8.2–§8.5 — preserved verbatim.

## Approach

Create `lib/core/radio_host/**` owning the block lifted from `_FaceScreenState`,
exposing a narrow interface shaped like Technical §3 with typed results (success
/ validation failure / cancellation / unavailable route / transport failure).
Reuse `lib/features/face/session_host.dart`'s injection seam and its existing
fakes — do not invent a second seam. Then hollow `face_screen.dart` so it
*consumes* a host rather than constructing services; the host is still created at
the same point in the tree for now, keeping `lib/app.dart`/`lib/main.dart`
untouched and out of territory. TASK-048 hoists it above the navigator;
TASK-061 deletes what remains of `face_screen.dart` much later, behind this task
in the dependency chain. Preserve today's tune semantics but expose one
serialized entry point for TASK-050 to build its coordinator on.

## Work Log
