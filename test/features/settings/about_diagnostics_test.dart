import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/settings/settings.dart';

RadioViewState view({
  Transport transport = Transport.direct,
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
      transport: transport,
      degraded: degraded,
    ),
    permissionDenied: permissionDenied,
    serviceFaultMessage: serviceFaultMessage,
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
    expect(all, contains('This network only On'));
    expect(all, contains('Active path Direct'));
    expect(all, isNot(contains('FloorEngine')));
    expect(all, isNot(contains('RadioSession')));
    expect(all, isNot(contains('Exception')));
    expect(all, isNot(contains('SVC FAULT')));
    expect(all, contains(SettingsCopy.serviceUnavailable));
    expect(all.toUpperCase(), isNot(contains('LOCAL')));
    expect(all.toUpperCase(), isNot(contains('LINKED')));
    expect(all.toUpperCase(), isNot(contains('AUTO')));
    expect(all.toLowerCase(), isNot(contains('channel')));
  });

  test('unresolved path is Connecting', () {
    final AboutDiagnostics about = buildAboutDiagnostics(
      view: view(transport: Transport.none),
      settings: const KeryxSettings(),
      version: '1.0.0+1',
    );
    final String all = [...about.summaryLines, ...about.detailLines].join('\n');
    expect(all, contains('Active path Connecting'));
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
