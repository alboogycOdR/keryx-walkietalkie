# TASK-037 Dossier — Face Integration (Real Transports, Live Roster, Settings/QR Nav, Sound)

## Overview
Reopened `lib/features/face/**` (TASK-017's territory) to replace every
hardcoded placeholder with the real thing: `RadioSessionController`
(TASK-035) drives the transport, `settingsProvider` (TASK-036/030) drives
config, the real `AudioSink`/`SfxEngine`/`SfxProjection` (TASK-033/034)
drive sound, and Event QR scan/export (TASK-007) are reachable from the
face.

## Implementation Summary

### Core design problem: real I/O vs. `flutter test`
`RadioSessionController.start()` opens real UDP sockets (LOCAL discovery/
signaling); `DeviceAudioSink` needs a real SoLoud native backend. Neither
runs inside `flutter test`. Solved with constructor-injected factories on
`FaceScreen`, defaulting to the real production paths:
- `sessionFactory` — defaults to building a real `RadioSessionController`
  wrapped in `RadioSessionHostAdapter`
- `audioSinkFactory` / `audioSinkDisposer` — defaults to `DeviceAudioSink`
  + its async `initialize()`/`dispose()`
- `identityFactory` — defaults to `IdentityRepository(SecureIdentityStore())
  .loadOrCreate()`. Discovered mid-task: this also hangs indefinitely under
  `flutter test` (no platform-channel implementation registered there, and
  it never throws — just never resolves), unrelated to the session/audio
  problem but blocking `_boot()` identically, so it got the same treatment.

`const FaceScreen()` in `lib/app.dart` is behaviorally unchanged (all
factories default to production paths). Tests construct
`FaceScreen(sessionFactory: ..., audioSinkFactory: ..., identityFactory: ...)`
with fakes — no real I/O anywhere in `test/features/face/**`.

### `SessionHost` seam (`lib/features/face/session_host.dart`, new file)
`RadioSessionController` (TASK-035, out of this task's `Owned_Paths`) is a
concrete class with no `implements` contract — it can't be mocked/subclassed
directly, and this task cannot add an interface to it without touching
`lib/services/session/**`. So the seam lives on this side instead:
`SessionHost` is the exact shape `FaceScreen` calls (`start`, `retune`,
`joinEvent`, `dispose`, `floorEngine`, `stations`); `RadioSessionHostAdapter`
is a near-pass-through wrapper around a real controller. Production's
default `sessionFactory` builds a real controller and wraps it; tests hand
`FaceScreen` a hand-written `FakeSessionHost` (in the test file) implementing
the interface directly, with zero real I/O.

### Session lifecycle / settings-triggered rebuild
`RadioSessionController`'s own dartdoc (TASK-035) is explicit that settings
are a construction-time snapshot: "a meaningfully different settings value
… needs a new `RadioSessionController` from the host." So "a settings
change made [in the back panel] is observed by the face without restart" is
satisfied at the `FaceScreen` boundary: a `settingsProvider` listener
compares the incoming `KeryxSettings` against the ones the active session
was built from; if any session-affecting field changed (`mode`,
`forceLocalOnly`, `relayUrl`, `tokenServiceUrl`, `totSeconds`,
`busyLockout`, `region`) the session is torn down and rebuilt with the new
settings. Everything else (squelch, roger beep, DSP intensity, dim mode…)
flows only downstream into `SfxProjection`/`SfxEngine` via a relayed
settings stream — no rebuild.

### Roster
`FaceScreen` subscribes to `SessionHost.stations` (a
`Stream<List<lib/services/session/StationInfo>>`) and maps each entry to
`lib/features/face/roster.dart`'s own `StationInfo` (a distinct, pre-existing
display type with the same field shape) via `_toRosterStation`. Two
`StationInfo` classes with the same name coexist by design — the barrel
export collision is handled with `hide`/qualified imports where both are
needed in the same file (see `face_screen.dart`'s imports and the test
file's top comment).

### Sound pipeline
Real `DeviceAudioSink` → `SfxEngine` → `SfxProjection`, fed by three relayed
broadcast streams (`RadioState`, `FloorEffect` via a proxy — see
`_floorEffectsProxy`'s dartdoc for why a proxy is needed — and
`KeryxSettings`). `SfxProjection.tick()` is polled every 50ms via a
`Timer.periodic` to advance the duck envelope. `PowerOn` is dispatched only
after the sink/projection are wired (not immediately in `_boot`, unlike the
pre-TASK-037 code) — `_radioStateStream` is fed via
`ref.listenManual(..., fireImmediately: true)` *before* `PowerOn` fires, so
the projection's edge-detection sees the off→boot transition and plays the
`powerOn` cue (a broadcast stream doesn't replay history to a late
subscriber).

### Settings navigation
`onSettings` now calls `Navigator.of(context).pushNamed(backPanelRouteName)`;
`lib/app.dart`'s `MaterialApp` registers that route to `BackPanelScreen`.
The previously reported recon bug (back-panel edits invisible to the face,
because the face held its own private `SettingsRepository` instance) is
fixed by construction: both now read through the same `settingsProvider`.

### Event QR entry points (disclosed decision)
Two icon buttons (scan / export) added to `StationListPanel`'s header —
that panel is already the face's natural "flip to a secondary screen" home
(FR-067's station list), so it's where a scan/export affordance reads as
belonging, rather than adding a seventh DS §4 band or overloading an
existing PTT-row key. `onScanQr`/`onExportQr` are nullable on `FaceView`/
`StationListPanel` so `face_view_test.dart`/`station_panel_test.dart` (not
in this task's `Owned_Paths`, pre-existing) keep passing unmodified. Scan
pushes `EventQrScanScreen`, whose `onTuned` calls `session.joinEvent`.
Export pushes `EventQrExportScreen` with a `NumberedEventLink` payload
builder for the currently tuned channel/code — only the numbered-channel
case is wired (a keyed-channel export needs a passphrase input this face
has no home for yet; the export screen's own `payloadBuilder` seam already
supports it for whoever wires that up later).

### `LocalFloorTransport` — deleted
Confirmed by repo-wide grep before deletion: nothing outside
`lib/features/face/local_floor_transport.dart` and the pre-TASK-037
`face_screen.dart` referenced it. Deleted; `face.dart`'s barrel export
removed.

### `onSayAgain` FR comment fix
Was wrongly citing FR-046 (the force-local-only privacy toggle); replay is
FR-065. Comment now cites FR-065 and states SAY AGAIN is a later-wave Pro
feature — handler itself stays an empty no-op (unchanged behavior).

### Disposal
`FaceScreen.dispose()` cancels/disposes, in order: the SFX tick `Timer`,
the stations/floor-effects `StreamSubscription`s, the `radioState`/
`settings` `ProviderSubscription`s, the `SfxProjection`, the `SfxEngine`,
the audio sink (via the injected disposer), the active `SessionHost`, the
three proxy `StreamController`s, and the pre-existing `_flipController`/
`_amplitude`. All async disposals use `unawaited()` (Flutter's `dispose()`
is synchronous), matching the pre-existing `unawaited(_bridge?.dispose())`
convention already established in this file.

## Acceptance Criteria Verification

1. **`LocalFloorTransport` no longer referenced** — ✓ file deleted, barrel
   updated; structural (a stale reference would fail `flutter analyze`'s
   import resolution, not just a runtime check).
2. **Stations panel live join/depart; empty renders `NO OTHER STATIONS`** —
   ✓ `station roster (criterion 2)` group, 2 tests
   (`test/features/face/face_screen_test.dart`).
3. **`onSettings` → `BackPanelScreen` and back; settings change observed
   without restart, widget-tested end-to-end through `settingsProvider`** —
   ✓ `settings (criterion 3)` group, 3 tests (nav round-trip,
   session-affecting rebuild, non-affecting no-rebuild), using
   `settingsStoreProvider.overrideWithValue(InMemorySettingsStore())`.
4. **QR scan → `joinEvent`; export screen reachable/renders, both
   widget-tested with fakes** — ✓ `event QR (criterion 4)` group, 2 tests.
   Scan test never mounts the real camera widget (captures the pushed
   route via a `NavigatorObserver` and calls `buildPage` directly),
   matching this repo's own established convention for testing QR-scan
   wiring without a platform camera channel.
5. **`SfxEngine`+projection constructed over injected sink; power-on plays
   `powerOn`, asserted via `RecordingAudioSink`** — ✓ `sound (criterion 5)`
   group, 1 test.
6. **All disposals verified; no leaked subscriptions after teardown** — ✓
   `disposal (criterion 6)` group, 1 test (`tester.takeException()` clean +
   `disposeCalled` assertion after replacing the whole widget tree).
7. **Full `flutter test` green, `flutter analyze` clean, `flutter build apk
   --debug` succeeds** — ✓ see Test_Evidence in PLAN.md.

## Territory Discipline
- **Modified:** `lib/features/face/face_screen.dart`, `face_view.dart`,
  `station_panel.dart`, `face.dart`, `lib/app.dart`,
  `test/features/face/face_screen_test.dart`
- **New:** `lib/features/face/session_host.dart`, `dossiers/TASK-037.md`
- **Deleted:** `lib/features/face/local_floor_transport.dart`
- **Untouched:** `lib/main.dart` (re-export only; no change needed),
  everything under `lib/services/session/**`, `lib/services/sound/**`,
  `lib/core/audio/**`, `lib/core/settings/**`, `lib/features/settings_panel/**`,
  `lib/features/event_qr/**` (all read-only consumption per
  `Spec_References`)
- Pre-existing `test/services/session/radio_session_controller_test.dart`
  (TASK-035's file) has 8 pre-existing `flutter analyze` warnings (unused
  imports/locals) — confirmed via `git log` to predate this task's diff
  entirely; not touched, not introduced here.

## Rework Round 1 (2026-08-22, response to ORCH's 13:30Z REWORK verdict)

All four blocking findings fixed on the same branch (`task/TASK-037-s5`),
commit `cdd6352`:

- **(a) 28dp touch targets.** `station_panel.dart`'s two `IconButton`s
  (`keryx-station-panel-scan`/`-export`) had
  `BoxConstraints(minWidth: 28, minHeight: 28)` — DS L134 requires >= 48dp
  unconditionally. Bumped both to 48x48; `iconSize` (18) unchanged, so the
  glyph stays visually small while the tappable area grows. New test
  asserts `tester.getSize` on both keys is >= `Size(48, 48)`.
  **Disclosed decision:** did not use a whole-screen
  `meetsGuideline(tester, androidTapTargetGuideline)` as literally suggested
  in the finding — running it found several *other*, pre-existing,
  out-of-territory tap targets below 48dp elsewhere on the face (the PTT
  key row's compact keys, the STN status-strip button), which are not this
  task's fix and would make the assertion fail for reasons unrelated to (a).
  The scoped `tester.getSize` check enforces DS L134 exactly where this
  task's fix applies without misattributing pre-existing debt.
- **(b) FR-043 entry point trapped in the 5s auto-flip window.**
  `GlassFlipController` gained `pauseAutoFlip()`/`resumeAutoFlipFresh()`.
  `face_screen.dart`'s `_onScanQr`/`_onExportQr` now pause the auto-flip
  before pushing the QR route (so it can't fire invisibly under a
  full-screen cover) and resume a *fresh* 5s window via
  `.whenComplete(...)` on return. Separately, `StationListPanel` now takes
  an `onInteraction` callback (wired to `flipController.flipToStations`,
  which restarts the timer even when already showing) fired on any
  pointer-down anywhere in the panel — covers the "found the panel, still
  hunting for the tiny icon" case without needing a route push at all. Two
  new widget tests: one simulates a slow interaction well past the original
  5s and confirms the icon is still reachable; one confirms the auto-flip
  doesn't fire while the scan screen is open and a fresh window starts on
  return.
- **(c) Criterion 6 checked without assertions.** Extended: `_Harness` now
  records `audioSinkDisposeCalled` via a custom `audioSinkDisposer`
  override, and the disposal test asserts it alongside
  `session.disposeCalled`. Left as documented rather than independently
  asserted: `SfxEngine`/`SfxProjection` have no observable "disposed" state
  of their own (see `sound.dart`) — `audioSinkDisposer` is the single
  externally-observable seam for "the whole sound pipeline (engine +
  projection + sink) was torn down together". The `_sfxTick` `Timer
  .periodic` cancellation proof (previously implicit — `flutter_test`'s
  `FakeAsync` fails any test that ends with a pending periodic timer) is now
  stated explicitly in the test's own comment.
- **(d) `_startSession` re-entrancy.** Added `_sessionGeneration`, a
  monotonic counter captured at entry and re-checked after `await
  session.start()`. A call that resumes to find itself superseded (a newer
  call landed or is still in flight) disposes the session it just built
  instead of assigning it to `_session` — closing the leak where two rapid
  session-affecting settings changes (no pump between them) left the first
  session's transport/sockets running forever and doubled up the
  `floorEngine.effects` -> `_floorEffectsProxy` feed. New widget test fires
  two `settingsProvider.save` calls back-to-back inside `tester.runAsync`
  (no await between them) and asserts exactly one of the resulting sessions
  ends up undisposed.

Non-blocking (e), fixed since cheap: `previousSession.dispose()` in
`_startSession` now routes a failure to `debugPrint` instead of a silently
swallowed zone error; `_retuneSession` wraps `session.retune` in try/catch
with the same telltale; `_onScanQr`'s `joinEvent` call now goes through a
new `_joinEvent` helper that shows a `SnackBar` on failure (FR-044: a
scan-while-LOCAL rejection is otherwise invisible). (f) and (g) left as
recorded in Review_Findings — (f) is ORCH-acknowledged unavoidable given the
test harness's own constraints, (g) is explicitly not this task's scope.

Full evidence (independently re-run, not just claimed): `flutter analyze`
0 new issues (same 8 pre-existing TASK-035 warnings, confirmed untouched);
`flutter test` 1048 passed / 0 failed / 40 skipped (1044 baseline + 4 net
new tests: touch-target size, two auto-flip-reachability tests, one
re-entrancy test); `flutter build apk --debug` succeeded,
225,948,227 bytes — identical to the pre-rework build (deterministic given
no dependency/asset changes).

## Process Notes
- Drafted via a bounded in-worktree implementation pass (same convention
  TASK-035 used), reviewed line-by-line, then verified independently:
  `flutter analyze` re-run myself (clean on every file this task touched),
  `flutter test` re-run myself (full suite), `flutter build apk --debug`
  re-run myself.
- Tooling note for future S5 sessions: PLAN.md edits via the `Edit` tool
  must target the **worktree's own local copy**
  (`wt-s5-walkietalkie-keryx/PLAN.md`), not the main-checkout path directly
  — the territory-firewall hook's `rel === 'PLAN.md'` legacy fast-path only
  fires when the edited path resolves relative to the worktree's own root.
  Editing the main-checkout copy directly trips a false Owned_Paths block.
  Workflow: edit the worktree's `PLAN.md` → `cp` it over the main-checkout
  copy → `scripts/plan_commit.sh`.

## Rework Round 2 (2026-08-22)

ORCH's round-2 review mutation-tested all four round-1 fixes in an isolated
scratch worktree and confirmed (d) and (b) both bite (deletion/weakening of
the production fix flips the corresponding test red) — no production
regression there. Two blocking findings, both test-efficacy defects with
**no production code change required**:

- **(h) DS L134 touch-target test asserted the wrong thing.** The test read
  `tester.getSize(find.byKey(...))` and checked it was `>= 48`. Under
  Material 3, `IconButton` routes through `ButtonStyleButton`'s
  `_InputPadding`, which pads the widget's *rendered hit-test box* to
  48x48 under `MaterialTapTargetSize.padded` regardless of the
  `constraints` actually passed to the `IconButton` — so `getSize` would
  return `>= 48` even reverted to the pre-fix `minWidth: 28, minHeight:
  28`. The assertion was structurally incapable of failing on the value it
  claimed to check, and the comment above it asserted otherwise (false).
  Fixed by asserting `IconButton.constraints` directly — the actual
  property fix (a) changed. Mutation-verified: reverting
  `station_panel.dart`'s constraints back to `28, 28` now fails this test.
- **(i) FR-043 reachability test's timeline never discriminated.** Two
  compounding defects: (1) the original pump totalled ~4s from the STN
  tap, which never exceeded the original 5s auto-flip window even with
  *no* interaction reset at all; (2) even fixed to exceed 5s, a single
  large `tester.pump(Duration(seconds: N))` renders exactly one frame
  *after* the elapsed time jumps — it does not step through the
  intermediate frames an in-flight animation needs. `GlassFlipper`'s
  flip-back is a 320ms `AnimationController.animateTo(0)`
  (`station_panel.dart`), so even after the un-reset timer fires,
  the "back" panel (with the scan icon) stayed mounted in the widget tree
  because the animation never got the frames to visually settle before
  the test's one post-jump frame rendered. Confirmed by instrumenting both
  `GlassFlipController` (print on `flipToStations`/`flipToGlass`) and
  `_GlassFlipperState.build` (print `_turn.value`/`showBack`) during
  debugging: `flipToGlass()` *was* firing at the 5s mark even under the
  mutation, but `_turn.value` stayed pinned at `1.0` (i.e. `showBack`
  stayed `true`) straight through the test's single big final pump — the
  rebuild triggered by `notifyListeners()` renders synchronously, before
  the newly-started `animateTo(0)` ticker gets a chance to advance.
  Fixed: elapse the first 4s in one pump (before interacting, matching the
  original intent), then after the interaction pump forward in twenty
  200ms increments (4s total) instead of one 4s jump — this gives any
  in-flight flip-back animation the frames it needs to actually settle
  before the final assertion. Mutation-verified: deleting
  `onInteraction: flipController.flipToStations` from `face_view.dart`
  now fails this test (the un-reset timer fires, the flip-back animation
  settles during the granular pumps, the scan icon is gone by the check);
  restoring the wiring passes it again.

Both mutations run and confirmed red-then-green myself before resubmitting,
per ORCH's explicit instruction in the round-2 finding. No production file
touched this round — `test/features/face/face_screen_test.dart` only.

Full evidence, independently re-run: `flutter analyze` 0 new issues (same 8
pre-existing TASK-035 warnings in `test/services/session/radio_session_controller_test.dart`,
confirmed untouched); `flutter test` (full suite) 1048 passed / 0 failed /
40 skipped — identical counts to the round-1 evidence, since no test was
added or removed, only two rewritten; `flutter build apk --debug`
succeeded, `build/app/outputs/flutter-apk/app-debug.apk`,
225,948,227 bytes — byte-identical to the round-1 build (expected, no
dependency/asset changes).
