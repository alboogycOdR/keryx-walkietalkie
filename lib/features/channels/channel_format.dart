import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioMode;

/// Two-digit channel/code label (Design §2.1 / §2.3; UX-FR-003).
String formatChannelCode(int channel, int privacyCode) {
  final String ch = channel.toString().padLeft(2, '0');
  final String code = privacyCode.toString().padLeft(2, '0');
  return 'CH $ch · $code';
}

/// Wire-mode as a short radio label. Never mixed into a single
/// "configured+effective" string — callers keep the two fields apart
/// (UX-FR-002).
String radioModeLabel(RadioMode mode) {
  return switch (mode) {
    RadioMode.local => 'LOCAL',
    RadioMode.linked => 'LINKED',
    RadioMode.auto => 'AUTO',
  };
}

/// Concise *actual* connection copy for the header indicator — effective
/// route, or Design §5's "Connection lost" when degraded. Never the
/// configured preference, and never AUTO as a live route (Technical §7).
String actualConnectionLabel(ConnectionCondition connection) {
  if (connection.degraded) {
    return 'Connection lost';
  }
  return connection.routeLabel;
}
