/// Wire constants for the radio foreground service (FR-103, TS §8.8).
///
/// Keep byte-identical with `RadioServiceContract` on the Kotlin side —
/// `test/services/platform/radio_service_native_contract_test.dart` asserts it.
abstract final class RadioServiceConstants {
  static const String methodChannel = 'za.co.basileia.keryx/radio_service';
  static const String eventChannel = 'za.co.basileia.keryx/radio_service_events';

  static const String methodStart = 'start';
  static const String methodStop = 'stop';
  static const String methodSetPhase = 'setPhase';
  static const String methodUpdateNotification = 'updateNotification';

  static const String argChannelLabel = 'channelLabel';
  static const String argSubtitle = 'subtitle';
  static const String argPhase = 'phase';

  static const String phaseIdle = 'idle';
  static const String phaseRx = 'rx';
  static const String phaseTx = 'tx';

  static const String eventTypeKey = 'type';
  static const String eventServiceKilled = 'serviceKilled';
  static const String eventPttAction = 'pttAction';
  static const String eventPowerOffAction = 'powerOffAction';

  static const String resultPttActionEnabled = 'pttActionEnabled';
}
