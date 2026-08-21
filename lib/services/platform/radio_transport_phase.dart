import 'radio_service_constants.dart';

/// Transport activity the native service needs for wake-lock / audio-focus.
///
/// Distinct from `RadioPhase` (lib/core/state, frozen, out of territory).
/// Host maps: `rxActive` → [rx], `tx`/`txRequest` → [tx], other powered-on
/// phases → [idle]. Power-off is [RadioServiceController.stop], not a phase.
enum RadioTransportPhase {
  idle,
  rx,
  tx;

  String get wireName => switch (this) {
    RadioTransportPhase.idle => RadioServiceConstants.phaseIdle,
    RadioTransportPhase.rx => RadioServiceConstants.phaseRx,
    RadioTransportPhase.tx => RadioServiceConstants.phaseTx,
  };

  static RadioTransportPhase fromWire(String raw) {
    switch (raw) {
      case RadioServiceConstants.phaseIdle:
        return RadioTransportPhase.idle;
      case RadioServiceConstants.phaseRx:
        return RadioTransportPhase.rx;
      case RadioServiceConstants.phaseTx:
        return RadioTransportPhase.tx;
      default:
        throw ArgumentError.value(raw, 'phase', 'expected idle|rx|tx');
    }
  }
}
