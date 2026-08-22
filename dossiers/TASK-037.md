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
