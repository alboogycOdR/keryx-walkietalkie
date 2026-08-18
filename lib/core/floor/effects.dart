import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/state/radio_state.dart';

/// Side effects emitted by [FloorEngine]. SFX, haptics, and the TASK-004
/// reducer subscribe; the engine itself never plays audio or mutates
/// [RadioState].
sealed class FloorEffect {
  const FloorEffect();
}

/// Host should dispatch [event] into [RadioReducer].
final class DispatchRadio extends FloorEffect {
  const DispatchRadio(this.event);

  final RadioEvent event;

  @override
  String toString() => 'DispatchRadio($event)';
}

/// Grant tone + grant haptic (FR-020 / FR-026). Host plays SFX.
final class GrantTone extends FloorEffect {
  const GrantTone();
}

/// Denied buzz (FR-022). [reason] is null when TX_REQ gave up after retries.
final class DenyBuzz extends FloorEffect {
  const DenyBuzz(this.reason);

  final FloorDenyReason? reason;

  @override
  String toString() => 'DenyBuzz(${reason?.wire ?? 'TIMEOUT'})';
}

/// TOT warning chirp at T−5 s (FR-023).
final class TotWarn extends FloorEffect {
  const TotWarn();
}

/// TOT hard cut + penalty tone at 0 (FR-023). Floor is released with this.
final class TotCut extends FloorEffect {
  const TotCut();
}

/// EMG indicator pinned until [EmgCleared] (FR-025).
final class EmgPinned extends FloorEffect {
  const EmgPinned(this.peer);

  final String peer;

  @override
  String toString() => 'EmgPinned($peer)';
}

/// Sender cleared the EMG pin.
final class EmgCleared extends FloorEffect {
  const EmgCleared(this.peer);

  final String peer;

  @override
  String toString() => 'EmgCleared($peer)';
}

/// Arbiter identity after a roster change. Election is immediate; the
/// 500 ms bound is the time until the new arbiter answers TX_REQ.
final class ArbiterChanged extends FloorEffect {
  const ArbiterChanged(this.peerId);

  final String peerId;

  @override
  String toString() => 'ArbiterChanged($peerId)';
}

/// Floor has been idle for [FloorTiming.floorIdleDebounce] (AUTO switch).
final class FloorIdleSettled extends FloorEffect {
  const FloorIdleSettled();
}
