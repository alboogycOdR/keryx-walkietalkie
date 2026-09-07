import 'package:keryx/core/floor/floor.dart' show FloorEngine;
import 'package:keryx/core/settings/settings_repository.dart' show TunedChannel;
import 'package:keryx/services/session/session.dart' show StationInfo;

/// Host-owned side state a UI layer needs alongside `radioStateProvider`
/// (Technical §3: "The host exposes current channel/code, configured mode,
/// effective route, phase, active speaker, station visibility, entitlement,
/// permission/service condition and pending operations").
///
/// Deliberately does **not** duplicate `RadioState`'s own fields (phase,
/// channel, code, mode, active speaker, …) — those already have exactly one
/// authoritative source, `radioStateProvider`, and Technical §3 is explicit
/// that a host must never "duplicate the reducer state into an
/// independently mutable UI state machine". This snapshot carries only the
/// state this host itself owns and that `radioStateProvider` has no field
/// for: permission/service condition, the live station roster, channel
/// memory, and read-only access to the authoritative [FloorEngine] for
/// TX-ownership truth. A richer presentation projection that combines this
/// with `RadioState` is TASK-046's `RadioViewState` job, not this one's.
class RadioHostSnapshot {
  const RadioHostSnapshot({
    this.micPermissionDenied = false,
    this.serviceFaultMessage,
    this.floorEngine,
    this.stations = const <StationInfo>[],
    this.channelMemory = const <TunedChannel>[],
  });

  /// Set once [FacePermissionGate.ensureMicrophone] resolves denied during
  /// [RadioHost.start]. Gates `BootCompleted` from ever being dispatched
  /// (the radio never reaches `idle`) — TASK-038's "radio does not enter
  /// idle" acceptance criterion, preserved verbatim.
  final bool micPermissionDenied;

  /// Non-null on a `RadioServiceFailed` event (TASK-038: "no crash, radio
  /// functional, condition surfaced on-face"). Cleared only by a fresh
  /// [RadioHost.start] — no automatic retry/recovery signal exists to clear
  /// it early, matching the pre-hoist disclosed decision.
  final String? serviceFaultMessage;

  /// The engine driving the currently-active session, or `null` before the
  /// first session has started / while one is being rebuilt. Technical §3:
  /// "The actual floor engine remains the source of truth for TX
  /// ownership" — a caller reads TX/emergency state and issues
  /// engine-level requests directly off this reference only for operations
  /// [RadioHost] itself does not narrowly expose (e.g. emergency pin/clear);
  /// [RadioHost.pressPtt]/[RadioHost.releasePtt]/[RadioHost.releaseLatch]
  /// remain the sanctioned path for ordinary PTT.
  final FloorEngine? floorEngine;

  /// Remote stations on the tuned channel, mirrored from the active
  /// session's own stream. Empty (not stale) whenever no session is
  /// active or one is being rebuilt — see `KeryxRadioHost`'s dartdoc for
  /// why a rebuild resets this eagerly rather than leaving the previous
  /// session's roster visible.
  final List<StationInfo> stations;

  /// Persisted channel-recall memory, mirrored from `SettingsRepository`
  /// after every successful [RadioHost.tune] and refreshed once more at
  /// [RadioHost.start] with whatever was already on disk.
  final List<TunedChannel> channelMemory;
}
