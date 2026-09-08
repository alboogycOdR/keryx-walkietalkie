import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/settings/settings.dart';

RadioViewState view({
  RadioMode configured = RadioMode.auto,
  RadioMode effective = RadioMode.local,
  bool degraded = false,
  bool permissionDenied = false,
  String? serviceFaultMessage,
}) {
  return RadioViewState(
    phase: RadioPhase.idle,
    emergency: false,
    latched: false,
    deniedFlash: false,
    connection: ConnectionCondition(
      configuredMode: configured,
      effectiveRoute: effective,
      degraded: degraded,
    ),
    permissionDenied: permissionDenied,
    serviceFaultMessage: serviceFaultMessage,
    channel: 7,
    privacyCode: 3,
    pendingTuningTarget: null,
    activeSpeakerPeerId: null,
    activeSpeakerCallsign: null,
    stations: const [],
    rosterCount: const KnownRosterCount(0),
    signalQuality: SignalQuality.unavailable,
    meterLevel: MeterLevel.decorative,
    isPro: false,
  );
}

void main() {
  test('ordinary diagnostics carry version and no internal names', () {
    final AboutDiagnostics about = buildAboutDiagnostics(
      view: view(serviceFaultMessage: 'SVC FAULT'),
      settings: const KeryxSettings(forceLocalOnly: true),
      version: '1.0.0+1',
    );
    final String all = [...about.summaryLines, ...about.detailLines].join('\n');
    expect(all, contains('1.0.0+1'));
    expect(all, contains('Local only On'));
    expect(all, contains('CH 07 · 03'));
    expect(all, isNot(contains('FloorEngine')));
    expect(all, isNot(contains('RadioSession')));
    expect(all, isNot(contains('Exception')));
    expect(all, isNot(contains('SVC FAULT')));
    expect(all, contains(SettingsCopy.serviceUnavailable));
  });

  test('sanitizeDiagnosticText strips exceptions and type names', () {
    expect(
      sanitizeDiagnosticText(
        'SocketException: Failed host lookup',
        fallback: 'Unavailable',
      ),
      'Unavailable',
    );
    expect(
      sanitizeDiagnosticText(
        'keryx.RadioSessionController',
        fallback: 'Unavailable',
      ),
      'Unavailable',
    );
    expect(
      sanitizeDiagnosticText('Connection lost', fallback: 'Unavailable'),
      'Connection lost',
    );
  });
}
