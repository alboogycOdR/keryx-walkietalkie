# TASK-100 — No-target boot must not attempt a relay room join

## Problem

`RadioSessionController.start()` (the no-target boot session) resolved
transport exactly like `switchTarget` — with a relay configured and
`forceLocalOnly` off, it minted a `/token` for the idle placeholder room
(`_idleRoomId = 'AAAAAAAAAAAAAAAA'`). The v2 token service's
`assert_room_member` (`token-svc/app/main.py:153-182`,
`token-svc/app/groups.py:383-395`) refuses any `room_id` that is not a real
`Group`/`DirectRoom` row with a deterministic 403 `not_member` — there is no
v2 lobby/idle room (Technical §6.4). So a relay-configured device's boot
session was **guaranteed** to fail, and `KeryxRadioHost` mislabelled the
failure "Couldn't reach the relay" even though the relay itself was fine.

## Fix

1. `RadioSessionController.start()` now unconditionally calls `_startLocal()`
   and dispatches `SetTransport(Transport.direct)` — it no longer calls
   `_resolveTransport()` at all, so `forceLocalOnly`/`relayUrl` have zero
   effect on the no-target boot session. It never constructs a
   `LinkedController`/`TokenClient`. `switchTarget` is untouched: it still
   calls `_resolveTransport()` and goes LINKED when a relay is configured
   and `forceLocalOnly` is off — that is the only place a real
   Group/DirectRoom room id arrives (TASK-101 makes the 1:1 case
   provisionable).

2. `KeryxRadioHost._startSession`'s failure-attribution catch now checks
   `error is SessionEstablishmentFailure` first and reads
   `error.transport` directly (`Transport.relay` → `SessionFailureKind.linked`,
   else `SessionFailureKind.local`) — falling back to the pre-existing
   settings-derived `_intendedFailureKind(settings)` guess only for a
   foreign `SessionHost` implementation or a bare timeout that never got as
   far as throwing the typed failure. This is what stops a LOCAL boot
   failure on a relay-configured device from being mislabelled "linked".

## Owned_Paths touched

- `lib/services/session/radio_session_controller.dart` — `start()` body +
  dartdoc.
- `lib/core/radio_host/keryx_radio_host.dart` — import `show` clause +
  the failure-attribution branch in `_startSession`'s catch.
- `test/services/session/radio_session_controller_test.dart` — see below.
- `test/core/radio_host/keryx_radio_host_test.dart` — see below.

## Test changes

`test/services/session/radio_session_controller_test.dart`:
- `transport matrix`: added two new cases — relay-configured +
  `forceLocalOnly=false` still resolves LOCAL for `start()` (`expectLocalBuilt:
  true`), and a dedicated test proving `start()` never invokes the injected
  `tokenClientFactory` (0 calls) even with a valid `relayUrl`.
- `switchTarget (v2, additive)`: added a case proving `switchTarget` on a
  relay-configured, non-local-only controller still goes LINKED
  (`debugLinkedController` non-null, `SetTransport(Transport.relay)`
  dispatched) — existing behaviour preserved, now explicitly asserted
  rather than only implied by the old (now-removed) `start()`-based LINKED
  path.
- `session-establishment bound (TASK-097)`: the LINKED-bound test previously
  proved via `controller.start()` with a relay configured (impossible to
  reach LINKED through `start()` anymore) is now proved through
  `switchTarget()` instead — same `_HangingLiveKitAdapter`/`_FastTokenClient`
  doubles, first a normal LOCAL `start()`, then a hung LINKED
  `switchTarget()`. Not deleted, retargeted with the rationale in the test
  name.

`test/core/radio_host/keryx_radio_host_test.dart`:
- Added `_ThrowingSessionHost` (throws the real `SessionEstablishmentFailure`
  naming an injected transport) and a `Harness.throwTypedFailure` seam.
- Two new tests in `session-establishment bound (TASK-097)`: a LOCAL typed
  failure on relay-configured settings reads `SessionFailureKind.local` (not
  `linked` — this is the criterion that mattered, proving the mislabel is
  fixed), and a LINKED typed failure on relay-unconfigured settings reads
  `SessionFailureKind.linked` (proves the typed path is symmetric, not just
  a one-off local-only special case).
- The existing `hangSessions`-based tests (bare `TimeoutException`, no typed
  failure) are untouched and still pass through the settings-derived
  fallback branch — proving that path is preserved for a foreign
  `SessionHost` implementation.

## Explicitly not touched

`KeryxSettings`, `_resolveTransport()`'s semantics for `switchTarget`,
`TokenClient`, `LinkedController`, the `SetTransport` dispatch shape.

## Test evidence

- `flutter test test/services/session/radio_session_controller_test.dart` —
  31/31 passed.
- `flutter test test/core/radio_host/keryx_radio_host_test.dart` — 22/22
  passed.
- `flutter test` (full suite) — 1446 passed, 40 skipped (all pre-existing
  PARKED FR-025 soak skips, project-owner decision 2026-08-21T17:05Z; none
  new), 0 failed.
- `flutter analyze --no-pub` — No issues found (31.6s).

## Product note for the owner (recorded per task description)

After this fix, Settings "Active path" reads "Direct" until a
contact/group is selected — honest, since no relay room is in use for the
idle session. Whether the relay is *reachable* is now signalled by
enrolment (`identityEnrolmentProvider`, TASK-099); surfacing that
specifically in Settings is a separate UX task, not this one.
