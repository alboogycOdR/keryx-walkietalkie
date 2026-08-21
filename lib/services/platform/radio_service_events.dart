import 'radio_service_constants.dart';

sealed class RadioServiceEvent {
  const RadioServiceEvent();
}

/// OEM/system killed the FGS without a user power-off (TS §8.8 → FR-105).
final class RadioServiceKilled extends RadioServiceEvent {
  const RadioServiceKilled();
}

/// Notification PTT action (Android 14+ where permitted, FR-103).
final class RadioServicePttAction extends RadioServiceEvent {
  const RadioServicePttAction();
}

/// Notification power-off action. Host should power the radio off.
final class RadioServicePowerOffAction extends RadioServiceEvent {
  const RadioServicePowerOffAction();
}

final class RadioServiceFailed extends RadioServiceEvent {
  const RadioServiceFailed(this.message);
  final String message;
}

RadioServiceEvent? radioServiceEventFromMap(Map<Object?, Object?> raw) {
  final map = Map<String, dynamic>.from(raw);
  switch (map[RadioServiceConstants.eventTypeKey]) {
    case RadioServiceConstants.eventServiceKilled:
      return const RadioServiceKilled();
    case RadioServiceConstants.eventPttAction:
      return const RadioServicePttAction();
    case RadioServiceConstants.eventPowerOffAction:
      return const RadioServicePowerOffAction();
    case 'error':
      return RadioServiceFailed(map['message'] as String? ?? 'radio service error');
    default:
      return null;
  }
}
