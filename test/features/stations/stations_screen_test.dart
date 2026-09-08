import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/stations/stations.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

import 'fake_radio_host.dart';

class SeededRadioStateController extends RadioStateController {
  SeededRadioStateController(this._seed);

  final RadioState _seed;

  @override
  RadioState build() => _seed;

  void seed(RadioState next) => state = next;
}

class StationsHarness {
  StationsHarness() : host = FakeRadioHost();

  final FakeRadioHost host;
  int scanCalls = 0;
  int exportCalls = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<StationsHarness> pumpStations(
    WidgetTester tester, {
    RadioState radio = const RadioState(
      phase: RadioPhase.idle,
      mode: RadioMode.local,
    ),
    KeryxSettings settings = const KeryxSettings(mode: RadioMode.local),
    RadioHostSnapshot snapshot = const RadioHostSnapshot(),
    Size surface = const Size(320, 720),
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final StationsHarness harness = StationsHarness();
    harness.host.emit(snapshot);
    final InMemorySettingsStore store = InMemorySettingsStore();
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(settings.toJson()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(harness.host),
          settingsStoreProvider.overrideWithValue(store),
          radioStateProvider.overrideWith(
            () => SeededRadioStateController(radio),
          ),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(),
          home: StationsScreen(
            onScan: () => harness.scanCalls++,
            onExport: () => harness.exportCalls++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  void expectNoUnsupportedAffordances() {
    expect(find.textContaining('online'), findsNothing);
    expect(find.textContaining('Online'), findsNothing);
    expect(find.textContaining('Contacts'), findsNothing);
    expect(find.textContaining('Favourite'), findsNothing);
    expect(find.textContaining('Favorite'), findsNothing);
    expect(find.textContaining('unread'), findsNothing);
    expect(find.textContaining('Unread'), findsNothing);
    expect(find.textContaining('History'), findsNothing);
    expect(find.textContaining('Message'), findsNothing);
    expect(find.textContaining('Inbox'), findsNothing);
  }

  testWidgets(
    'renders known callsigns and Visible presence from the host stream '
    '(Design §2.4; Technical §1)',
    (WidgetTester tester) async {
      await pumpStations(
        tester,
        snapshot: const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
            StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
          ],
        ),
      );

      expect(find.text('ALPHA-1'), findsOneWidget);
      expect(find.text('BRAVO-2'), findsOneWidget);
      expect(find.text(StationsCopy.presenceVisible), findsNWidgets(2));
      expect(find.byKey(StationsScreenKeys.list), findsOneWidget);
      expect(find.text(StationsCopy.localCount(2)), findsOneWidget);
    },
  );

  testWidgets('live join/depart updates while open without a parent rebuild '
      '(Design §2.4; UX-FR-040; VT-024)', (WidgetTester tester) async {
    final StationsHarness harness = await pumpStations(tester);

    expect(find.text('ALPHA-1'), findsNothing);
    expect(find.byKey(StationsScreenKeys.empty), findsOneWidget);

    // Emit on the host stream only — do not pumpWidget / setState the
    // parent. A screen that waited on a parent rebuild would stay empty.
    harness.host.emit(
      const RadioHostSnapshot(
        stations: <StationInfo>[
          StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
          StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ALPHA-1'), findsOneWidget);
    expect(find.text('BRAVO-2'), findsOneWidget);
    expect(find.byKey(StationsScreenKeys.empty), findsNothing);

    harness.host.emit(
      const RadioHostSnapshot(
        stations: <StationInfo>[
          StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ALPHA-1'), findsNothing);
    expect(find.text('BRAVO-2'), findsOneWidget);
    expect(harness.host.methodLog, isEmpty);
  });

  testWidgets('unknown identity uses the fallback; peer ID is never shown '
      '(UX-FR-026)', (WidgetTester tester) async {
    await pumpStations(
      tester,
      snapshot: const RadioHostSnapshot(
        stations: <StationInfo>[
          StationInfo(peerId: 'abcdefghij', callsign: 'abcdefghij'),
          StationInfo(peerId: 'klmnopqrst', callsign: 'not a name!!!'),
          StationInfo(peerId: 'uvwx234567', callsign: 'CHARLIE-3'),
        ],
      ),
    );

    expect(find.text(StationsCopy.unknownStation), findsNWidgets(2));
    expect(find.text('CHARLIE-3'), findsOneWidget);
    expect(find.text('abcdefghij'), findsNothing);
    expect(find.text('klmnopqrst'), findsNothing);
    expect(find.text('uvwx234567'), findsNothing);
    expect(find.textContaining('abcdefghij'), findsNothing);
  });

  testWidgets(
    'placeholder signalQuality is marked unavailable and never rendered '
    'as measured full bars (Technical §1.1; UX-FR-045; VT-024)',
    (WidgetTester tester) async {
      await pumpStations(
        tester,
        snapshot: const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(
              peerId: 'peer-aaa',
              callsign: 'ALPHA-1',
              signalQuality: StationInfo.placeholderSignalQuality,
            ),
          ],
        ),
      );

      expect(find.text(StationsCopy.qualityUnavailable), findsOneWidget);
      expect(find.byKey(StationsScreenKeys.quality), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.signal_cellular_4_bar), findsNothing);
      expect(find.byIcon(Icons.signal_cellular_alt), findsNothing);
      expect(find.text('9'), findsNothing);
      expect(find.textContaining('S9'), findsNothing);
      expect(find.textContaining('S-9'), findsNothing);
      expect(find.textContaining('full'), findsNothing);
    },
  );

  testWidgets(
    'incomplete LINKED roster states member list unavailable, never a '
    'verified zero (Design §2.4; UX-FR-046; VT-024)',
    (WidgetTester tester) async {
      await pumpStations(
        tester,
        radio: const RadioState(phase: RadioPhase.idle, mode: RadioMode.linked),
        settings: const KeryxSettings(mode: RadioMode.linked),
      );

      expect(
        find.textContaining(StationsCopy.linkedUnavailable),
        findsOneWidget,
      );
      expect(find.byKey(StationsScreenKeys.linkedCount), findsOneWidget);
      expect(find.text(StationsCopy.localCount(0)), findsOneWidget);
      expect(find.text('0 members'), findsNothing);
      expect(find.text('Members: 0'), findsNothing);
      expect(find.text('0 stations'), findsNothing);
      expect(find.textContaining('0 member'), findsNothing);
    },
  );

  testWidgets('local station count and LINKED member count are distinct fields '
      '(UX-FR-046)', (WidgetTester tester) async {
    await pumpStations(
      tester,
      radio: const RadioState(phase: RadioPhase.idle, mode: RadioMode.linked),
      settings: const KeryxSettings(mode: RadioMode.linked),
      snapshot: const RadioHostSnapshot(
        stations: <StationInfo>[
          StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
          StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
        ],
      ),
    );

    expect(find.text(StationsCopy.localCount(2)), findsOneWidget);
    expect(find.textContaining(StationsCopy.linkedUnavailable), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(StationsScreenKeys.localCount)).dy,
      lessThan(
        tester.getTopLeft(find.byKey(StationsScreenKeys.linkedCount)).dy,
      ),
    );
    // LOCAL-only screen must not show the LINKED field.
  });

  testWidgets('LOCAL roster does not render a LINKED member-count field '
      '(UX-FR-046)', (WidgetTester tester) async {
    await pumpStations(
      tester,
      snapshot: const RadioHostSnapshot(
        stations: <StationInfo>[
          StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
        ],
      ),
    );

    expect(find.text(StationsCopy.localCount(1)), findsOneWidget);
    expect(find.byKey(StationsScreenKeys.linkedCount), findsNothing);
    expect(find.textContaining(StationsCopy.linkedUnavailable), findsNothing);
  });

  testWidgets('empty state renders Design §5 copy plus current-channel context '
      '(Design §2.4/§5)', (WidgetTester tester) async {
    await pumpStations(
      tester,
      radio: const RadioState(
        phase: RadioPhase.idle,
        mode: RadioMode.local,
        channel: 7,
        privacyCode: 3,
      ),
    );

    expect(find.text(StationsCopy.empty), findsOneWidget);
    expect(find.byKey(StationsScreenKeys.empty), findsOneWidget);
    expect(find.text('CH 07 · 03'), findsOneWidget);
    expect(find.byKey(StationsScreenKeys.channelContext), findsOneWidget);
  });

  testWidgets(
    'Event QR scan/export are reachable; no contacts/favourite/message/'
    'unread affordance (Design §2.4; UX-FR-008; UX-D09)',
    (WidgetTester tester) async {
      final StationsHarness harness = await pumpStations(
        tester,
        snapshot: const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
          ],
        ),
      );

      expect(find.byKey(StationsScreenKeys.scan), findsOneWidget);
      expect(find.byKey(StationsScreenKeys.export), findsOneWidget);
      expect(find.byTooltip(StationsCopy.scanEventQr), findsOneWidget);
      expect(find.byTooltip(StationsCopy.exportEventQr), findsOneWidget);

      await tester.tap(find.byKey(StationsScreenKeys.scan));
      await tester.pumpAndSettle();
      expect(harness.scanCalls, 1);
      expect(harness.exportCalls, 0);

      await tester.tap(find.byKey(StationsScreenKeys.export));
      await tester.pumpAndSettle();
      expect(harness.exportCalls, 1);
      expect(harness.host.methodLog, isEmpty);
      expect(harness.host.joinEventCalls, isEmpty);

      expectNoUnsupportedAffordances();
    },
  );

  testWidgets('state cues carry text + icon; QR actions meet 48 dp '
      '(Design §3.2/§3.3; UX-FR-022)', (WidgetTester tester) async {
    await pumpStations(tester);

    expect(find.text(StationsCopy.qualityUnavailable), findsOneWidget);
    expect(find.byIcon(Icons.signal_cellular_null), findsOneWidget);
    expect(
      tester.getSize(find.byKey(StationsScreenKeys.scan)).height,
      greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
    );
    expect(
      tester.getSize(find.byKey(StationsScreenKeys.export)).width,
      greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
    );
  });

  test('source never reads StationInfo.signalQuality or paints S-meter bars '
      '(UX-FR-045; VT-024)', () {
    final String src = File(
      'lib/features/stations/stations_screen.dart',
    ).readAsStringSync();
    expect(src.contains('signalQuality'), isFalse);
    expect(src.contains('placeholderSignalQuality'), isFalse);
    expect(RegExp(r'generate\s*\(\s*9').hasMatch(src), isFalse);
    expect(src.contains('LinearProgressIndicator'), isFalse);
    expect(src.contains('signal_cellular_4_bar'), isFalse);
    expect(src.contains('signal_cellular_alt'), isFalse);
  });

  test('source never renders a numeric LINKED member count (UX-FR-046)', () {
    final String src = File(
      'lib/features/stations/stations_screen.dart',
    ).readAsStringSync();
    expect(src.contains('KnownRosterCount'), isFalse);
    expect(src.contains('rosterCount.count'), isFalse);
    expect(src.contains('Members:'), isFalse);
  });

  test('no literal colour values in the stations feature (Design §3.2)', () {
    const List<String> paths = <String>[
      'lib/features/stations/stations_screen.dart',
      'lib/features/stations/station_copy.dart',
      'lib/features/stations/station_identity.dart',
    ];
    for (final String path in paths) {
      final String src = File(path).readAsStringSync();
      expect(src.contains('Color(0x'), isFalse, reason: path);
      expect(RegExp(r'\bColors\.').hasMatch(src), isFalse, reason: path);
    }
  });
}
