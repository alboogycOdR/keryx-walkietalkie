# TASK-038 Dossier — Runtime Permissions + Foreground Service Lifecycle Wiring

## Overview
Same `lib/features/face/**` territory as TASK-037, reopened strictly serially
after it. Wires two previously-built-but-never-invoked pieces into
`FaceScreen`: runtime permission grants (`permission_handler`, allocated by
TASK-033) and `RadioServiceController` (TASK-026's Android foreground-service
facade, `lib/services/platform/**`).

## Implementation Summary

### Permissions (`lib/features/face/permission_gate.dart`, new file)
`FacePermissionGate` is the constructor-injected seam (same pattern as
`sessionFactory`/`audioSinkFactory`/`identityFactory` from TASK-037):
`permission_handler`'s real plugin has no registered implementation under
`flutter test` at all (unlike `flutter_soloud`/identity storage, there isn't
even a fake backend shipped with the package), so production wraps
`DeviceFacePermissionGate` and tests inject a hand-written fake.

**Status-check-before-request is the entire mechanism for the API<33
acceptance criterion.** Every method reads `.status` first and only calls
`.request()` if not already granted. Neither `POST_NOTIFICATIONS` nor
`NEARBY_WIFI_DEVICES` is a runtime-checked permission before Android 13 —
`permission_handler`'s own native side reports `.status` as already granted
on those OS versions — so `.request()` is naturally never reached pre-33,
with **no explicit SDK-version branch needed on the Dart side** (which would
have required a new platform channel; `android/**` is not in this task's
`Owned_Paths`). The algorithm itself is factored out as a pure,
`@visibleForTesting` top-level function (`ensurePermissionOutcome`) taking
injected `status`/`request` closures, specifically so it can be unit-tested
directly (`test/features/face/permission_gate_test.dart`) without needing any
platform-channel fake at all — there being none available for this plugin.

`FaceScreen._boot` requests microphone first (blocking — awaited, gates
`BootCompleted`), then notifications + nearby-Wi-Fi together (awaited as a
pair purely so tests can observe both deterministically, not because either
gates anything). **Denied-mic disclosed decision:** the boot sequence never
dispatches `BootCompleted`, so `RadioState.phase` stays at `boot` forever
(no retry path — a fresh app boot is the only way to re-request; out of this
task's scope to add a "settings changed, re-check" reconciliation loop). A
non-modal telltale (`'MIC REQUIRED'`) is shown instead of any dialog, via a
new `FaceView.statusOverride` parameter (below).

### `FaceView.statusOverride` (`lib/features/face/face_view.dart`)
`RadioState` (frozen, `lib/core/state`) has no field for "permission denied"
or "service fault" — both conditions live entirely on this side. Rather than
inventing a new `KeryxTelltale` (which lives in the also-frozen
`lib/features/display/**`), `FaceView` gained one new optional
`String? statusOverride` parameter: when non-null it replaces
`_statusLine()`'s computed text outright (checked first, before any
`RadioState`-derived branch); `null` (the default) leaves every existing
caller's behaviour byte-identical. `FaceScreen._statusOverride()` picks
`'MIC REQUIRED'` over `'SVC FAULT'` when both are somehow true (disclosed
priority, not expected to matter in practice).

### Foreground service (`RadioServiceController`, TASK-026)
Constructor-injected the same way: `radioServiceFactory` defaults to
`ChannelRadioServiceController.production()`; tests inject
`ChannelRadioServiceController(platform: FakeRadioServicePlatform())` — that
fake already ships from `lib/services/platform/platform.dart` (TASK-026's own
facade tests use it), so no new test double needed hand-writing for this
half of the task at all.

- **Start on power-on**: `radioService.start(channelLabel: 'CH XX · YY')`
  (exact format TASK-038's description names, matching
  `KeryxLcdDisplay.primaryLine`'s own zero-padding) right after `PowerOn` is
  dispatched. A `start()` throw is caught at this boundary — logged via
  `debugPrint`, `_serviceFaultMessage` set — so a native fault degrades
  gracefully rather than crashing `_boot`; the radio still finishes booting
  to `idle` (mic permission is independent of the service).
- **Phase mapping**: `_syncServicePhase`, hooked into the existing
  `radioStateProvider` listener (the same one that feeds `SfxProjection`),
  maps `rxActive→rx`, `tx`/`txRequest→tx`, everything else powered-on→`idle`,
  de-duped against the last phase actually pushed so an unrelated state
  emission (a roster update) doesn't re-issue an identical `setPhase` call.
  No-ops before the service is running.
- **Retune → updateNotification**: `_retuneSession` (existing TASK-037
  method) now also calls `service.updateNotification(channelLabel: ...)`
  after the session-layer retune, gated only on `service.isRunning` —
  independent of session state, so a tune that arrives before the very first
  `session.start()` resolves still gets the notification label right the
  moment the service exists.
- **Event handling** (`_onRadioServiceEvent`, a Dart 3 sealed-class switch
  over the four `RadioServiceEvent` subtypes):
  - `RadioServiceKilled` → `_dispatch(PowerOff())`. No silent zombie.
  - `RadioServicePttAction` → toggles `_floorEngine.requestTransmit()`/
    `releaseTransmit()` based on `_floorEngine.isTransmitting` — **not**
    `radioStateProvider.phase`. Disclosed reasoning: `radioStateProvider`
    only reflects `FloorEngine`'s `DispatchRadio` effects once something
    bridges them (TASK-035's `RadioStateBridge`, wired inside
    `RadioSessionController` in production, out of this task's
    `Owned_Paths`) — reading the provider here would be one hop further
    from the truth than every other PTT entry point on this screen already
    is. Both `requestTransmit`/`releaseTransmit` are idempotent no-ops in
    every state where the toggle guess is wrong, so this is robust either
    way, not just usually-right.
  - `RadioServicePowerOffAction` → `_dispatch(PowerOff())` **only**. Original
    draft also called `_radioService.stop()`, but
    `ChannelRadioServiceController`'s own `_onEvent` already marks itself
    not-running the instant this event arrives — confirmed against
    `test/services/platform/radio_service_controller_test.dart`
    ("notification PTT and power-off actions surface as events": asserts
    `controller.isRunning == false` right after this event with **no**
    `stop()` call from the host). Calling `.stop()` here would be a
    same-tick no-op (native has already torn the FGS down by the time Dart
    hears about it); removed for accuracy, matches the `RadioServiceKilled`
    handler's shape exactly.
  - `RadioServiceFailed` → `debugPrint` + `_serviceFaultMessage` set (the
    same telltale as a `start()` throw). No crash; session/floor/sound keep
    running untouched.
- **Disposal**: `_radioServiceSub` cancelled and `_radioService.dispose()`
  called in `FaceScreen.dispose()` (which itself calls `stop()` internally),
  alongside the existing session/sink/engine teardown.

### Inherited non-blocking follow-ups from TASK-037 round 3, both closed here
- **(j)** `GlassFlipController.resumeAutoFlipFresh` now also guards on
  `_disposed`, so a QR-route `.whenComplete` callback firing after the
  controller itself was disposed can no longer arm a fresh `Timer` on a dead
  controller.
- **(k)** Restated rather than re-verified from scratch: this task did not
  re-run TASK-037's whole-screen `meetsGuideline` sweep (out of scope — this
  task touched no touch-target-relevant widgets), so the specific failure
  text from that finding is not reproduced here. Flagged again for whoever
  next opens `lib/features/ptt/**`/`lib/features/face/status_strip.dart`,
  the two areas TASK-037's dossier named.

## Testing notes / traps hit

- **`FakeSessionHost`'s `FloorEngine` needs `updateRoster({self})` to
  self-grant.** `FloorEngine._rosterConverged` requires either
  `_rosterDeclared` (only set by an explicit `updateRoster` call — a
  constructor-default `{self}` roster does **not** count, per that class's
  own dartdoc) **or** the clock not having moved past `_joinedAt` yet. The
  fixture uses a real `WallClock()`, and by the time any `await`-based test
  interacts with it that window has already closed — every PTT-toggle
  assertion failed with `isTransmitting == false` until `FakeSessionHost`'s
  constructor was given the same `updateRoster({localPeerId})` call
  production's `RadioSessionController` makes from its own discovery/
  presence wiring (`lib/services/session/radio_session_controller.dart:350`,
  out of territory, read-only). This is a fixture correctness fix, not new
  test-target behaviour.
- **Two async broadcast-stream hops between a simulated platform event and
  `FaceScreen` observing it**: `FakeRadioServicePlatform.events` →
  `ChannelRadioServiceController.events` → `FaceScreen`'s own subscription.
  Every `simulate*`/`emit` call in the test file is followed by **two**
  `tester.pump()` calls, not one — the first pumps microtasks through the
  controller's internal `_onEvent` forwarding, the second through
  `FaceScreen`'s own listener and its `setState`.
- **`ChStepperButton`'s `keryx-stepper-up` tap** trips the same known
  `flutter_test` false-positive hit-test warning class TASK-037's settings-key
  test already documented (transform-scaled render stack, tap correctly
  reaches the `Listener` regardless) — `warnIfMissed: false`, same
  precedent.

## Test Evidence
- `flutter analyze` (repo-wide): 8 pre-existing warnings, all in
  `test/services/session/radio_session_controller_test.dart` (TASK-035's
  file, predates this task's diff — confirmed via `git log`), zero issues in
  any file this task touched.
- `flutter test` (full suite, unfiltered): **1064 passed, 0 failed, 40
  skipped** (the pre-parked FR-025 soak skips, unrelated). New tests this
  task added: `test/features/face/permission_gate_test.dart` (4 unit tests
  on `ensurePermissionOutcome`), `test/features/face/face_view_test.dart`
  (+2, `statusOverride`), `test/features/face/face_screen_test.dart` (+9:
  2 permissions, 4 foreground-service-lifecycle, 2 event-handling, 2
  `RadioServiceFailed`-path — one group name says "criterion 3" for the
  event group vs "criterion 2" for lifecycle, matching the acceptance
  checklist's own numbering).
- `flutter build apk --debug`: succeeded,
  `build/app/outputs/flutter-apk/app-debug.apk`, 252,348,429 bytes (not
  compared against TASK-033/037's earlier figures as a baseline — per those
  tasks' own caveat, debug APK size is cache-state dependent).
- `android/app/src/main/AndroidManifest.xml` (read-only check, `android/**`
  is out of `Owned_Paths`): confirmed `RECORD_AUDIO`, `POST_NOTIFICATIONS`,
  and `NEARBY_WIFI_DEVICES` (with `minSdkVersion="33"` +
  `neverForLocation`) are all already declared from TASK-019/026's earlier
  work — nothing manifest-side needed changing for this task's
  `permission_handler` calls to have something real to request.

## Work Log
- 2026-08-22 [S5]: Claimed, implemented permission gate + foreground-service
  wiring + `statusOverride` telltale + the two inherited TASK-037 follow-ups,
  full test suite green, debug build green. Submitted `needs_review`.
