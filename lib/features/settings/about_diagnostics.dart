import 'package:keryx/core/presentation/presentation.dart'
    show ConnectionCondition, RadioViewState;
import 'package:keryx/core/settings/settings_repository.dart'
    show KeryxSettings;

import 'settings_copy.dart';

/// Ordinary-user diagnostics. Never includes raw exception text, Dart
/// type names, or internal service identifiers (Design §5).
class AboutDiagnostics {
  const AboutDiagnostics({
    required this.summaryLines,
    required this.detailLines,
  });

  final List<String> summaryLines;
  final List<String> detailLines;
}

final _bannedFragments = <String>[
  'exception',
  'error:',
  'stack',
  'floorengine',
  'radiosession',
  'sessionhost',
  'livekit',
  'webrtc',
  'controller',
  'tokenclient',
  'flutter',
];

String sanitizeDiagnosticText(String? raw, {required String fallback}) {
  if (raw == null) {
    return fallback;
  }
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  final String lower = trimmed.toLowerCase();
  for (final String banned in _bannedFragments) {
    if (lower.contains(banned)) {
      return fallback;
    }
  }
  // Dotted identifier that looks like a type or package (FooBar.baz).
  if (trimmed.contains('.') &&
      RegExp(r'[A-Z][A-Za-z0-9]+(\.[A-Za-z0-9]+){1,}').hasMatch(trimmed)) {
    return fallback;
  }
  return trimmed;
}

AboutDiagnostics buildAboutDiagnostics({
  required RadioViewState view,
  required KeryxSettings settings,
  required String version,
}) {
  final ConnectionCondition connection = view.connection;
  final String path = connection.routeLabel;
  final String networkOnly = settings.forceLocalOnly ? 'On' : 'Off';
  final String mic = view.permissionDenied
      ? SettingsCopy.microphoneRequired
      : SettingsCopy.microphoneOk;
  final String service = view.serviceFaultMessage == null
      ? SettingsCopy.serviceOk
      : SettingsCopy.serviceUnavailable;
  final String link = connection.degraded
      ? SettingsCopy.connectionLost
      : SettingsCopy.connectionOk;

  return AboutDiagnostics(
    summaryLines: <String>['Version $version', link, mic],
    detailLines: <String>[
      'Version $version',
      'Active path $path',
      'This network only $networkOnly',
      link,
      mic,
      service,
    ],
  );
}
