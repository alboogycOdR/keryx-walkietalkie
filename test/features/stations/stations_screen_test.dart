import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/stations/stations.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

import '../talk/a11y_matrix_support.dart';
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

ConnectionCondition routeCondition(RadioMode route) => ConnectionCondition(
  configuredMode: route,
  effectiveRoute: route,
  degraded: false,
);

RadioViewState makeView({
  List<StationInfo> stations = const <StationInfo>[],
  RosterCount? rosterCount,
  SignalQuality signalQuality = const UnavailableSignalQuality(),
  RadioMode effectiveRoute = RadioMode.local,
  RadioMode configuredMode = RadioMode.local,
  int channel = 1,
  int privacyCode = 0,
  String? activeSpeakerPeerId,
}) {
  return RadioViewState(
    phase: RadioPhase.idle,
    emergency: false,
    latched: false,
    deniedFlash: false,
    connection: ConnectionCondition(
      configuredMode: configuredMode,
      effectiveRoute: effectiveRoute,
      degraded: false,
    ),
    permissionDenied: false,
    serviceFaultMessage: null,
    channel: channel,
    privacyCode: privacyCode,
    pendingTuningTarget: null,
    activeSpeakerPeerId: activeSpeakerPeerId,
    activeSpeakerCallsign: null,
    stations: stations,
    rosterCount: rosterCount ?? KnownRosterCount(stations.length),
    signalQuality: signalQuality,
    meterLevel: MeterLevel.decorative,
    isPro: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpView(
    WidgetTester tester,
    RadioViewState view, {
    Size surface = const Size(320, 720),
    bool streamFault = false,
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: StationsView(
          view: view,
          streamFault: streamFault,
          onScan: () {},
          onExport: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<StationsHarness> pumpStations(
    WidgetTester tester, {
    RadioState radio = const RadioState(
      phase: RadioPhase.idle,
      mode: RadioMode.local,
    ),
    KeryxSettings settings = const KeryxSettings(mode: RadioMode.local),
    RadioHostSnapshot snapshot = const RadioHostSnapshot(),
    Size surface = const Size(320, 720),
    Brightness brightness = Brightness.dark,
    bool embedded = false,
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
          theme: keryxUxThemeData(brightness: brightness),
          home: StationsScreen(
            onScan: () => harness.scanCalls++,
            onExport: () => harness.exportCalls++,
            embedded: embedded,
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

  void expectNoQualityBars() {
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.signal_cellular_4_bar), findsNothing);
    expect(find.byIcon(Icons.signal_cellular_alt), findsNothing);
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
    'placeholder StationInfo.signalQuality is not rendered as measured '
    'full bars when the projection says unavailable '
    '(Technical §1.1; UX-FR-045; VT-024)',
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
      expect(find.text(StationsCopy.qualityMeasured(9)), findsNothing);
      expectNoQualityBars();
      expect(find.text('9'), findsNothing);
      expect(find.textContaining('S9'), findsNothing);
      expect(find.textContaining('S-9'), findsNothing);
      expect(find.textContaining('full'), findsNothing);
    },
  );

  testWidgets(
    'incomplete LINKED roster states member list unavailable, never a '
    'verified zero or Design §5 empty copy (Design §2.4; UX-FR-046; VT-024)',
    (WidgetTester tester) async {
      await pumpStations(
        tester,
        radio: const RadioState(phase: RadioPhase.idle, mode: RadioMode.linked),
        settings: const KeryxSettings(mode: RadioMode.linked),
      );

      expect(
        find.text(
          StationsCopy.incompleteRoster(routeCondition(RadioMode.linked)),
        ),
        findsOneWidget,
      );
      expect(find.byKey(StationsScreenKeys.linkedCount), findsOneWidget);
      expect(find.text(StationsCopy.localCount(0)), findsNothing);
      expect(find.byKey(StationsScreenKeys.empty), findsNothing);
      expect(find.text(StationsCopy.empty), findsNothing);
      expect(find.text('0 members'), findsNothing);
      expect(find.text('Members: 0'), findsNothing);
      expect(find.text('0 stations'), findsNothing);
      expect(find.textContaining('0 member'), findsNothing);
    },
  );

  testWidgets('unresolved incomplete roster is labelled Connecting, never '
      'AUTO as an effective route (Technical §7; UX-FR-002)', (
    WidgetTester tester,
  ) async {
    await pumpStations(
      tester,
      radio: const RadioState(phase: RadioPhase.idle, mode: RadioMode.auto),
      settings: const KeryxSettings(mode: RadioMode.auto),
    );

    expect(
      find.text(
        StationsCopy.incompleteRoster(routeCondition(RadioMode.auto)),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Connecting'), findsOneWidget);
    expect(find.textContaining('AUTO'), findsNothing);
    expect(find.textContaining(StationsCopy.linkedCountLabel), findsNothing);
    expect(find.textContaining('LINKED'), findsNothing);
    expect(find.text(StationsCopy.localCount(0)), findsNothing);
    expect(find.byKey(StationsScreenKeys.empty), findsNothing);
  });

  testWidgets(
    'LINKED with locally-visible stations lists them but does not present '
    'stations.length as a verified total (UX-FR-046)',
    (WidgetTester tester) async {
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

      expect(find.text('ALPHA-1'), findsOneWidget);
      expect(find.text('BRAVO-2'), findsOneWidget);
      expect(
        find.text(
          StationsCopy.incompleteRoster(routeCondition(RadioMode.linked)),
        ),
        findsOneWidget,
      );
      expect(find.byKey(StationsScreenKeys.linkedCount), findsOneWidget);
      expect(find.byKey(StationsScreenKeys.localCount), findsNothing);
      expect(find.text(StationsCopy.localCount(2)), findsNothing);
      expect(find.byKey(StationsScreenKeys.empty), findsNothing);
    },
  );

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
    expect(find.text(StationsCopy.localCount(0)), findsOneWidget);
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

  testWidgets('count text comes from KnownRosterCount, not stations.length '
      '(UX-FR-046; review finding 2)', (WidgetTester tester) async {
    await pumpView(
      tester,
      makeView(
        stations: const <StationInfo>[
          StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
        ],
        rosterCount: const KnownRosterCount(5),
      ),
    );

    expect(find.text(StationsCopy.localCount(5)), findsOneWidget);
    expect(find.text(StationsCopy.localCount(1)), findsNothing);
    expect(find.text('ALPHA-1'), findsOneWidget);
  });

  testWidgets('UnavailableRosterCount with empty stations is unknown, not a '
      'verified empty room (VT-024; review finding 1)', (
    WidgetTester tester,
  ) async {
    await pumpView(
      tester,
      makeView(
        stations: const <StationInfo>[],
        rosterCount: const UnavailableRosterCount(),
        effectiveRoute: RadioMode.linked,
      ),
    );

    expect(
      find.text(
        StationsCopy.incompleteRoster(routeCondition(RadioMode.linked)),
      ),
      findsOneWidget,
    );
    expect(find.text(StationsCopy.localCount(0)), findsNothing);
    expect(find.byKey(StationsScreenKeys.empty), findsNothing);
    expect(find.text(StationsCopy.empty), findsNothing);
  });

  testWidgets('MeasuredSignalQuality renders the S-meter reading and ignores '
      'StationInfo.placeholderSignalQuality (UX-FR-045; review finding 4)', (
    WidgetTester tester,
  ) async {
    await pumpView(
      tester,
      makeView(
        stations: const <StationInfo>[
          StationInfo(
            peerId: 'peer-aaa',
            callsign: 'ALPHA-1',
            signalQuality: StationInfo.placeholderSignalQuality,
          ),
        ],
        rosterCount: const KnownRosterCount(1),
        signalQuality: const MeasuredSignalQuality(3),
      ),
    );

    expect(find.text(StationsCopy.qualityMeasured(3)), findsOneWidget);
    expect(find.text(StationsCopy.qualityUnavailable), findsNothing);
    expect(find.text(StationsCopy.qualityMeasured(9)), findsNothing);
    expect(find.textContaining('S9'), findsNothing);
    expectNoQualityBars();
    expect(find.byIcon(Icons.network_check), findsOneWidget);
    expect(find.byIcon(Icons.signal_cellular_null), findsNothing);
  });

  testWidgets(
    'host stream error leaves a stated-unavailable screen, not a stale '
    'snapshot (review finding 6)',
    (WidgetTester tester) async {
      final StationsHarness harness = await pumpStations(
        tester,
        snapshot: const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
          ],
        ),
      );
      expect(find.text('ALPHA-1'), findsOneWidget);

      harness.host.emitError();
      await tester.pumpAndSettle();

      expect(find.text('ALPHA-1'), findsNothing);
      expect(find.text(StationsCopy.streamUnavailable), findsOneWidget);
      expect(find.byKey(StationsScreenKeys.empty), findsNothing);
      expect(find.text(StationsCopy.empty), findsNothing);
      expect(find.text(StationsCopy.localCount(0)), findsNothing);
      expect(find.byKey(StationsScreenKeys.list), findsNothing);

      harness.host.emit(
        const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BRAVO-2'), findsOneWidget);
      expect(find.text(StationsCopy.streamUnavailable), findsNothing);
      expect(find.text(StationsCopy.localCount(1)), findsOneWidget);
    },
  );

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

  group('TASK-057 round 2 — responsive matrix + rendered guidelines', () {
    testWidgets(
      'renders without exception across the full responsive matrix '
      '(320 lp, larger phone, landscape, text scale 2.0)',
      (tester) async {
        await expectResponsiveMatrix(tester, (t, size) async {
          await t.pumpWidget(const SizedBox.shrink());
          await pumpStations(
            t,
            snapshot: const RadioHostSnapshot(
              stations: <StationInfo>[
                StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
                StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
              ],
            ),
            surface: size,
          );
        });
      },
    );

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(dark)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpStations(
        tester,
        snapshot: const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
          ],
        ),
        brightness: Brightness.dark,
      );
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(light)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpStations(
        tester,
        snapshot: const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
          ],
        ),
        brightness: Brightness.light,
      );
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });
  });

  group('TASK-076 — embedded mode', () {
    testWidgets(
      'embedded: true renders no app bar; current-channel context and QR '
      'actions move to the top of the body (ADR-002 A1; Design §2.4)',
      (WidgetTester tester) async {
        final StationsHarness harness = await pumpStations(
          tester,
          snapshot: const RadioHostSnapshot(
            stations: <StationInfo>[
              StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
            ],
          ),
          embedded: true,
        );

        expect(find.byType(AppBar), findsNothing);
        expect(find.byKey(StationsScreenKeys.title), findsNothing);
        expect(find.byKey(StationsScreenKeys.channelContext), findsOneWidget);
        expect(
          find.byKey(StationsScreenKeys.embeddedActions),
          findsOneWidget,
        );
        expect(find.byKey(StationsScreenKeys.scan), findsOneWidget);
        expect(find.byKey(StationsScreenKeys.export), findsOneWidget);

        await tester.tap(find.byKey(StationsScreenKeys.scan));
        await tester.tap(find.byKey(StationsScreenKeys.export));
        expect(harness.scanCalls, 1);
        expect(harness.exportCalls, 1);
      },
    );

    testWidgets(
      'embedded: false (default) is unchanged: app bar with title and '
      'channel context, QR actions in the app bar, no embedded action row',
      (WidgetTester tester) async {
        await pumpStations(
          tester,
          snapshot: const RadioHostSnapshot(
            stations: <StationInfo>[
              StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
            ],
          ),
        );

        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byKey(StationsScreenKeys.title), findsOneWidget);
        expect(find.byKey(StationsScreenKeys.channelContext), findsOneWidget);
        expect(
          find.byKey(StationsScreenKeys.embeddedActions),
          findsNothing,
        );
        expect(find.byKey(StationsScreenKeys.scan), findsOneWidget);
        expect(find.byKey(StationsScreenKeys.export), findsOneWidget);
      },
    );
  });

  group('TASK-076 — rows: avatar, presence, speaking indicator', () {
    testWidgets(
      'rows show an initials avatar, callsign and honest presence '
      '(Design §2.4)',
      (WidgetTester tester) async {
        await pumpStations(
          tester,
          snapshot: const RadioHostSnapshot(
            stations: <StationInfo>[
              StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
            ],
          ),
        );

        expect(find.byType(CircleAvatar), findsOneWidget);
        expect(find.text('A1'), findsOneWidget);
        expect(find.text('ALPHA-1'), findsOneWidget);
        expect(find.text(StationsCopy.presenceVisible), findsOneWidget);
      },
    );

    testWidgets(
      'only the active speaker row shows the speaking indicator '
      '(Design §2.4; RadioViewState.activeSpeakerPeerId)',
      (WidgetTester tester) async {
        await pumpView(
          tester,
          makeView(
            stations: const <StationInfo>[
              StationInfo(peerId: 'peer-aaa', callsign: 'ALPHA-1'),
              StationInfo(peerId: 'peer-bbb', callsign: 'BRAVO-2'),
            ],
            activeSpeakerPeerId: 'peer-bbb',
          ),
        );

        expect(find.byKey(StationsScreenKeys.speaking), findsOneWidget);
        expect(find.text('Speaking'), findsOneWidget);

        final Semantics bravoRow = tester.widget<Semantics>(
          find.ancestor(
            of: find.text('BRAVO-2'),
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is Semantics && (w.properties.label ?? '').contains(
                    'speaking',
                  ),
            ),
          ),
        );
        expect(bravoRow.properties.label, contains('speaking'));
      },
    );

    testWidgets(
      'no station is speaking: indicator never renders',
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

        expect(find.byKey(StationsScreenKeys.speaking), findsNothing);
        expect(find.text('Speaking'), findsNothing);
      },
    );
  });
}
