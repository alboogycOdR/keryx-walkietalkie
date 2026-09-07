import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;
import 'package:keryx/features/event_qr/event_link.dart';

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

/// Result of [RadioHost.tune]. `unavailableRoute` never applies to a tune —
/// there is always a channel/code numeral to accept or reject — so only
/// the other four outcomes are exposed as named constructors.
class TuneResult {
  const TuneResult._(this.outcome, [this.message]);

  const TuneResult.success() : this._(RadioHostOutcome.success);

  const TuneResult.validationFailure(String reason)
    : this._(RadioHostOutcome.validationFailure, reason);

  const TuneResult.cancelled() : this._(RadioHostOutcome.cancelled);

  const TuneResult.transportFailure(String reason)
    : this._(RadioHostOutcome.transportFailure, reason);

  final RadioHostOutcome outcome;

  /// Human-diagnostic detail for logs/dossiers only — never surfaced
  /// verbatim to the UI as a message the user is expected to parse
  /// (Technical §3).
  final String? message;

  bool get isSuccess => outcome == RadioHostOutcome.success;

  @override
  String toString() => 'TuneResult($outcome${message != null ? ', $message' : ''})';
}

/// Result of [RadioHost.joinEvent]. `unavailableRoute` covers
/// `SessionHost.joinEvent`'s own documented precondition ("requires an
/// already-active LINKED chain") and the no-session-yet case.
class JoinResult {
  const JoinResult._(this.outcome, [this.message]);

  const JoinResult.success() : this._(RadioHostOutcome.success);

  const JoinResult.validationFailure(String reason)
    : this._(RadioHostOutcome.validationFailure, reason);

  const JoinResult.cancelled() : this._(RadioHostOutcome.cancelled);

  const JoinResult.unavailableRoute(String reason)
    : this._(RadioHostOutcome.unavailableRoute, reason);

  const JoinResult.transportFailure(String reason)
    : this._(RadioHostOutcome.transportFailure, reason);

  final RadioHostOutcome outcome;
  final String? message;

  bool get isSuccess => outcome == RadioHostOutcome.success;

  @override
  String toString() => 'JoinResult($outcome${message != null ? ', $message' : ''})';
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

  /// Serialized entry point for a channel/code change (Technical §6: "the
  /// successor must serialize competing tune requests"). Concurrent calls
  /// run strictly in submission order — a call never observes another
  /// call's partially-applied state.
  Future<TuneResult> tune(int channel, int code);

  /// Applies a settings snapshot: always feeds the sound pipeline, and
  /// additionally serializes a full session reconstruction if any
  /// session-affecting field actually changed (Technical §7). Presentation
  /// -only fields never rebuild communication.
  Future<void> applySettings(KeryxSettings settings);

  /// Requires an already-active session with a LINKED chain — returns
  /// [JoinResult.unavailableRoute] otherwise, never an unhandled throw.
  Future<JoinResult> joinEvent(EventLinkPayload payload);

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
