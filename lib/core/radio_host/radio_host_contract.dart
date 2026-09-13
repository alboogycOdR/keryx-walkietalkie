import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;

import 'radio_host_snapshot.dart';

/// Outcome classification shared by every host operation that can fail —
/// Technical §3: "Typed results should distinguish successful operation,
/// validation failure, cancellation, unavailable route and transport
/// failure. The UI must not parse exception text to determine state."
enum RadioHostOutcome {
  success,
  validationFailure,
  cancelled,
  unavailableRoute,
  transportFailure,
}

/// Narrow, testable, app-scoped radio lifecycle contract — Technical §3's
/// illustrative `RadioHost` interface, adopted with the same operation
/// names (this task's own naming call is to keep them, not invent
/// alternates). Illustrative, not a demand, per the spec text — but every
/// operation the spec names is present.
///
/// No visual widget may start a transport, publish microphone media,
/// construct a floor engine or own the foreground service (Technical §2) —
/// every one of those capabilities is reachable only through this
/// interface (or, for read-only TX-ownership truth, [RadioHostSnapshot
/// .floorEngine] — Technical §3: "The actual floor engine remains the
/// source of truth for TX ownership").
abstract interface class RadioHost {
  /// Latest emitted snapshot — synchronous, always available, never a
  /// `Future`. Seed a UI's first paint with this before subscribing to
  /// [changes].
  RadioHostSnapshot get current;

  /// Emits a new [RadioHostSnapshot] every time host-owned state changes.
  /// Does not replay [current] to a new subscriber — mirrors every other
  /// broadcast stream already used in this file's territory
  /// (`_radioStateStream` et al. in the pre-hoist `FaceScreen`).
  Stream<RadioHostSnapshot> get changes;

  /// Idempotent: a second call while the first is still in flight shares
  /// the same in-flight boot rather than starting a second one (Technical
  /// §4: "A single boot operation is in flight; concurrent boots share or
  /// serialize its result").
  Future<void> start();

  /// Releases any local transmit, stops the foreground service if running,
  /// and dispatches the off state. Does not dispose the host — a
  /// subsequent [start] is not part of this task's contract (no caller
  /// needs it yet) but nothing here forecloses it.
  Future<void> powerOff();

  /// Applies a settings snapshot: always feeds the sound pipeline, and
  /// additionally serializes a full session reconstruction if any
  /// session-affecting field actually changed (Technical §7). Presentation
  /// -only fields never rebuild communication.
  Future<void> applySettings(KeryxSettings settings);

  /// Authoritative command path entry points (Technical §5.1) — forward
  /// straight to `FloorEngine.requestTransmit`/`releaseTransmit` and never
  /// synthesize a granted/denied result themselves; the actual grant flows
  /// back through [RadioHostSnapshot.floorEngine]'s effects into
  /// `RadioState`.
  void pressPtt();
  void releasePtt();

  /// A deliberate latch release — same authoritative call as [releasePtt],
  /// exposed separately because a latch is owned by the UI layer (whether
  /// a press should stay keyed) while the release action itself is always
  /// this host's job (Technical §4: "A route-level PTT gesture is released
  /// on cancellation/disposal. A deliberate latch is owned by the
  /// persistent host and survives ordinary navigation until explicit
  /// release, TOT or authoritative termination").
  void releaseLatch();

  /// Idempotent — a second call after the first completes is a no-op
  /// (Verification VT-004: "Repeated disposal is safe"). Releases every
  /// subscription, timer, session and audio resource, and guarantees no
  /// locally transmitting track survives it (Technical §4; PTS §8.5).
  Future<void> dispose();
}

/// v2 (TASK-102, Technical §3.2 "Replaces this KERYX ID" / §4.2 `POST
/// /v2/identity`, `PATCH /v2/identity/callsign`): optional capability a
/// [RadioHost] may support — reload the device identity from storage and
/// rebuild the active session so directory enrolment, presence and the
/// LINKED `/token` mint all move to the new key **together**, with no
/// restart.
///
/// Deliberately **not** a member of [RadioHost] itself. [RadioHost] is
/// implemented by several test doubles outside this task's `Owned_Paths`
/// (`test/app_shell/fake_radio_host.dart`,
/// `test/features/radio_controls/fake_radio_host.dart`,
/// `test/features/talk/fake_radio_host.dart`,
/// `test/core/presentation/radio_view_intents_test.dart`) — adding a
/// required member to that interface would break every one of them to
/// implement a capability only Settings' restore/rename flow needs. Same
/// "additive interface, `is`-checked by the caller" shape TASK-107 used
/// for `SessionHostEngineEvents` so unrelated fakes keep compiling
/// unchanged. [KeryxRadioHost] implements this in addition to [RadioHost];
/// a caller that only holds a bare [RadioHost] checks `host is
/// RadioIdentityReloader` before calling it.
abstract interface class RadioIdentityReloader {
  /// Reloads identity via the host's own identity source (storage — the
  /// same one `IdentityRepository.restoreKeyPair`/`setCallsign` just wrote
  /// to) and reconstructs the active session with it, exactly like a
  /// session-affecting settings change (Technical §7) but keyed off a
  /// changed identity instead. Never throws — directory enrolment inside
  /// the rebuilt session is already best-effort and logs its own failures
  /// (mirrors [RadioHost.applySettings]).
  ///
  /// The caller is responsible for invalidating any Riverpod-side cached
  /// read of identity (e.g. `identityProvider`) *before* calling this, so
  /// the directory-enrolment chain this triggers resolves the same fresh
  /// identity rather than a stale cached one.
  Future<void> reloadIdentity();
}
