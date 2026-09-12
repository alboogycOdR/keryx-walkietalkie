/// TASK-045 — persistent, app-scoped radio lifecycle owner.
///
/// This is the exact block that used to live inside `_FaceScreenState`
/// (`lib/features/face/face_screen.dart`, TS §1.1 / ADR-001 §6), hoisted out
/// unchanged in substance: identity/settings bootstrap, permission
/// coordination, `SessionHost`/`RadioSessionController`, the `FloorEngine`
/// (via the session), the `SfxEngine`/`SfxProjection`/`AudioSink` pipeline,
/// the Android `RadioServiceController` and the station stream. Nothing
/// here constructs a new floor engine, session, transport or audio
/// pipeline — see `session_host.dart`'s injection seam, reused verbatim.
///
/// **Riverpod-agnostic by design.** This module never imports
/// `flutter_riverpod` — every read of ambient Riverpod state
/// (`loadSettings`, `readRadioState`, `dispatch`, `rememberChannel`) and
/// every subscription (`listenRadioState`, `listenSettings`) is a plain
/// callback supplied by the caller (today: `FaceScreen`'s `ConsumerState`,
/// via its own `ref`; TASK-048 wires the same callbacks from `app.dart`
/// once the host moves above the navigator). This keeps
/// `lib/core/radio_host/**` trivially unit-testable with fakes (see
/// `test/core/radio_host/**`) and keeps `radioStateProvider` as the single,
/// un-duplicated source of truth for `RadioState` — this host never copies
/// reducer state into a second mutable state machine (Technical §3: "Never
/// duplicate the reducer state into an independently mutable UI state
/// machine").
library;

export 'radio_host_contract.dart';
export 'radio_host_snapshot.dart';
export 'keryx_radio_host.dart';
export 'session_host.dart';
export 'permission_gate.dart';
