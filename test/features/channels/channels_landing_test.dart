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
import 'package:keryx/features/channels/channels.dart';
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

class LandingHarness {
  LandingHarness() : host = FakeRadioHost(), watched = <int>[];

  final FakeRadioHost host;
  final List<int> watched;
  int openTalkCalls = 0;
  int selectChannelCalls = 0;
  int tuneSucceededCalls = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LandingHarness> pumpLanding(
    WidgetTester tester, {
    RadioState radio = const RadioState(
      phase: RadioPhase.idle,
      mode: RadioMode.local,
    ),
    KeryxSettings settings = const KeryxSettings(mode: RadioMode.auto),
    bool includeNav = true,
    Size surface = const Size(320, 720),
    Brightness brightness = Brightness.dark,
    bool embedded = false,
    bool openTalkEnabled = true,
    bool reportTuneSuccess = false,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final LandingHarness harness = LandingHarness();
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
          home: ChannelsLanding(
            onOpenTalk: openTalkEnabled ? () => harness.openTalkCalls++ : null,
            onSelectChannel: () => harness.selectChannelCalls++,
            embedded: embedded,
            onTuneSucceeded: reportTuneSuccess
                ? () => harness.tuneSucceededCalls++
                : null,
            watchChannel: harness.watched.add,
            persistentNavigation: includeNav
                ? NavigationBar(
                    selectedIndex: 0,
                    destinations: const <NavigationDestination>[
                      NavigationDestination(
                        icon: Icon(Icons.radio),
                        label: 'Channels',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
                  )
                : null,
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
    expect(find.textContaining('member'), findsNothing);
    expect(find.textContaining('Member'), findsNothing);
    expect(find.textContaining('unread'), findsNothing);
    expect(find.textContaining('Contacts'), findsNothing);
    expect(find.textContaining('History'), findsNothing);
  }

  testWidgets(
    'content order is connection, card, Open Talk, recents, Select, nav '
    '(Design §2.1)',
    (WidgetTester tester) async {
      await pumpLanding(tester);

      double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;

      expect(
        top(ChannelsLandingKeys.connection),
        lessThan(top(ChannelsLandingKeys.currentCard)),
      );
      expect(
        top(ChannelsLandingKeys.currentCard),
        lessThan(top(ChannelsLandingKeys.openTalk)),
      );
      expect(
        top(ChannelsLandingKeys.openTalk),
        lessThan(top(ChannelsLandingKeys.recentSection)),
      );
      expect(
        top(ChannelsLandingKeys.recentSection),
        lessThan(top(ChannelsLandingKeys.selectChannel)),
      );
      expect(
        top(ChannelsLandingKeys.selectChannel),
        lessThan(tester.getTopLeft(find.byType(NavigationBar)).dy),
      );
    },
  );

  testWidgets(
    'current-channel card shows two-digit channel/code, configured mode '
    'and effective route as separate fields (UX-FR-002)',
    (WidgetTester tester) async {
      await pumpLanding(
        tester,
        radio: const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
          channel: 7,
          privacyCode: 3,
        ),
        settings: const KeryxSettings(mode: RadioMode.auto),
      );

      expect(find.text('CH 07 · 03'), findsOneWidget);
      expect(find.text('Configured AUTO'), findsOneWidget);
      expect(find.text('Effective LOCAL'), findsOneWidget);
      expect(find.text('Status Hold to talk'), findsOneWidget);
      expect(find.text('Configured LOCAL'), findsNothing);
      expect(find.text('Effective AUTO'), findsNothing);
    },
  );

  testWidgets(
    'embedded mode omits the app bar and brand while default mode retains '
    'the existing keyed structure (ADR-002 A1)',
    (WidgetTester tester) async {
      await pumpLanding(tester);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byKey(ChannelsLandingKeys.brand), findsOneWidget);
      expect(find.byKey(ChannelsLandingKeys.openTalk), findsOneWidget);
      expect(find.byKey(ChannelsLandingKeys.selectChannel), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpLanding(tester, embedded: true);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(ChannelsLandingKeys.brand), findsNothing);
      expect(find.byKey(ChannelsLandingKeys.openTalk), findsOneWidget);
      expect(find.byKey(ChannelsLandingKeys.selectChannel), findsOneWidget);
    },
  );

  testWidgets(
    'a null Open Talk callback hides all Talk shortcuts and successful '
    'recall notifies once (ADR-002 A1)',
    (WidgetTester tester) async {
      final LandingHarness harness = await pumpLanding(
        tester,
        embedded: true,
        openTalkEnabled: false,
        reportTuneSuccess: true,
      );
      harness.host.emit(
        const RadioHostSnapshot(
          channelMemory: <TunedChannel>[
            TunedChannel(channel: 7, privacyCode: 3),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ChannelsLandingKeys.openTalk), findsNothing);
      await tester.tap(find.byKey(ChannelsLandingKeys.currentCard));
      await tester.pumpAndSettle();
      expect(harness.openTalkCalls, 0);

      await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
      await tester.pumpAndSettle();
      expect(harness.tuneSucceededCalls, 1);

      harness.host.autoResult = const TuneResult.transportFailure('offline');
      await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
      await tester.pumpAndSettle();
      expect(harness.tuneSucceededCalls, 1);

      harness.host.autoResult = const TuneResult.cancelled();
      await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
      await tester.pumpAndSettle();
      expect(harness.tuneSucceededCalls, 1);
    },
  );

  testWidgets(
    'current row is marked and pinned; recent rows retain real values and '
    'the 64dp selectable treatment (ADR-002 A1)',
    (WidgetTester tester) async {
      final LandingHarness harness = await pumpLanding(tester);
      harness.host.emit(
        const RadioHostSnapshot(
          channelMemory: <TunedChannel>[
            TunedChannel(channel: 7, privacyCode: 3),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final Finder current = find.byKey(ChannelsLandingKeys.currentCard);
      final Finder recent = find.byKey(ChannelsLandingKeys.recentEntry(7, 3));
      expect(find.text('Current'), findsOneWidget);
      expect(
        tester.getTopLeft(current).dy,
        lessThan(tester.getTopLeft(recent).dy),
      );
      expect(tester.getSize(recent).height, greaterThanOrEqualTo(64));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    },
  );

  testWidgets('degraded connection reports Connection lost without rewriting '
      'configured mode (UX-FR-002; Design §5)', (WidgetTester tester) async {
    await pumpLanding(
      tester,
      radio: const RadioState(
        phase: RadioPhase.linkDegraded,
        mode: RadioMode.linked,
        isNoLink: true,
      ),
      settings: const KeryxSettings(mode: RadioMode.linked),
    );

    expect(find.text('Configured LINKED'), findsOneWidget);
    expect(find.text('Effective LINKED'), findsOneWidget);
    expect(find.text('Status Connection lost'), findsOneWidget);
    expect(find.text('Connection lost'), findsWidgets);
  });

  testWidgets(
    'recent list renders real values in order, deduped; tap tunes and '
    'does nothing else (UX-FR-004; VT-020)',
    (WidgetTester tester) async {
      final LandingHarness harness = await pumpLanding(tester);

      harness.host.emit(
        const RadioHostSnapshot(
          channelMemory: <TunedChannel>[
            TunedChannel(channel: 7, privacyCode: 3),
            TunedChannel(channel: 12, privacyCode: 1),
            TunedChannel(channel: 7, privacyCode: 3),
            TunedChannel(channel: 2, privacyCode: 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CH 07 · 03'), findsOneWidget);
      expect(find.text('CH 12 · 01'), findsOneWidget);
      expect(find.text('CH 02 · 00'), findsOneWidget);
      expect(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)), findsOneWidget);

      await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(12, 1)));
      await tester.pumpAndSettle();

      expect(harness.host.tuneCalls, <(int, int)>[(12, 1)]);
      expect(harness.openTalkCalls, 0);
      expect(harness.selectChannelCalls, 0);
    },
  );

  testWidgets('empty memory shows the neutral message and still offers Select '
      'channel (Design §2.1)', (WidgetTester tester) async {
    await pumpLanding(tester);

    expect(find.text('No recently tuned channels.'), findsOneWidget);
    expect(find.text('Recently tuned'), findsNothing);
    expect(find.text('Select channel'), findsOneWidget);
  });

  testWidgets(
    'no online/member/unread/contact/history affordance, even when the '
    'host snapshot carries stations (Design §2.1; UX-FR-008; UX-D05)',
    (WidgetTester tester) async {
      final LandingHarness harness = await pumpLanding(tester);
      harness.host.emit(
        const RadioHostSnapshot(
          stations: <StationInfo>[
            StationInfo(peerId: 'peer-aaa', callsign: 'KRYX1'),
            StationInfo(peerId: 'peer-bbb', callsign: 'KRYX2'),
          ],
          channelMemory: <TunedChannel>[
            TunedChannel(channel: 7, privacyCode: 3),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expectNoUnsupportedAffordances();
      expect(find.text('KRYX1'), findsNothing);
      expect(find.text('KRYX2'), findsNothing);
      expect(find.textContaining('peer-aaa'), findsNothing);
    },
  );

  testWidgets('watchChannel is never invoked — no 99-channel presence sweep '
      '(Design §2.1)', (WidgetTester tester) async {
    final LandingHarness harness = await pumpLanding(tester);
    expect(harness.watched, isEmpty);
    expect(harness.host.startCalls, 0);
    expect(harness.host.methodLog, isEmpty);

    harness.host.emit(
      const RadioHostSnapshot(
        channelMemory: <TunedChannel>[
          TunedChannel(channel: 1, privacyCode: 0),
          TunedChannel(channel: 99, privacyCode: 38),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.watched, isEmpty);
    expect(harness.host.methodLog, isEmpty);
  });

  testWidgets(
    'current channel is one tap (card or Open Talk) and navigation does '
    'not retune (UX-FR-005)',
    (WidgetTester tester) async {
      final LandingHarness harness = await pumpLanding(
        tester,
        radio: const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
          channel: 4,
          privacyCode: 8,
        ),
      );

      expect(find.text('CH 04 · 08'), findsOneWidget);

      await tester.tap(find.byKey(ChannelsLandingKeys.currentCard));
      await tester.pumpAndSettle();
      expect(harness.openTalkCalls, 1);
      expect(harness.host.tuneCalls, isEmpty);

      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      expect(harness.openTalkCalls, 2);
      expect(harness.host.tuneCalls, isEmpty);

      await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.pumpAndSettle();
      expect(harness.selectChannelCalls, 1);
      expect(harness.host.tuneCalls, isEmpty);
      expect(find.text('CH 04 · 08'), findsOneWidget);
    },
  );

  testWidgets('state cues carry icon + text; Open Talk / Select meet 48 dp '
      '(Design §3.2/§3.3; UX-FR-022)', (WidgetTester tester) async {
    await pumpLanding(tester);

    expect(
      tester.getSize(find.byKey(ChannelsLandingKeys.openTalk)).height,
      greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
    );
    expect(
      tester.getSize(find.byKey(ChannelsLandingKeys.selectChannel)).height,
      greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
    );
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.text('Status Hold to talk'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_outlined), findsOneWidget);
  });

  test('source does not sweep 1..99 or call watchChannel (Design §2.1)', () {
    final String src = File(
      'lib/features/channels/channels_landing.dart',
    ).readAsStringSync();
    expect(src.contains('maximumChannel'), isFalse);
    expect(RegExp(r'for\s*\([^)]*99').hasMatch(src), isFalse);
    expect(src.contains('watchChannel?.call'), isFalse);
    expect(src.contains('watchChannel!('), isFalse);
  });

  testWidgets('recall failure is visibly represented and offers a real retry '
      'path — not a silently discarded TuneResult (TASK-067; UX-FR-009)', (
    WidgetTester tester,
  ) async {
    final LandingHarness harness = await pumpLanding(tester);
    harness.host.autoResult = const TuneResult.transportFailure(
      'radio unreachable',
    );
    harness.host.emit(
      const RadioHostSnapshot(
        channelMemory: <TunedChannel>[TunedChannel(channel: 7, privacyCode: 3)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
    await tester.pumpAndSettle();

    expect(harness.host.tuneCalls, <(int, int)>[(7, 3)]);
    expect(find.byKey(ChannelsLandingKeys.recallFeedback), findsOneWidget);
    expect(
      find.text(
        'Could not complete the retune. The active channel may be unchanged.',
      ),
      findsOneWidget,
    );
    final Finder retry = find.byKey(ChannelsLandingKeys.recallRetry);
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();

    // Retry re-submits the exact same target — never a different one,
    // never a rollback (Technical §6, the same policy TASK-050 built).
    expect(harness.host.tuneCalls, <(int, int)>[(7, 3), (7, 3)]);
  });

  testWidgets('a pending recall retune shows progress and blocks a competing '
      'recall tap (TASK-067; matches TASK-050 Design §2.3)', (
    WidgetTester tester,
  ) async {
    final LandingHarness harness = await pumpLanding(tester);
    harness.host.holdTunes = true;
    harness.host.emit(
      const RadioHostSnapshot(
        channelMemory: <TunedChannel>[
          TunedChannel(channel: 7, privacyCode: 3),
          TunedChannel(channel: 12, privacyCode: 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
    await tester.pump();

    expect(find.byKey(ChannelsLandingKeys.recallProgress), findsOneWidget);

    // A competing tap on another recent entry while busy must not
    // dispatch a second tune.
    await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(12, 1)));
    await tester.pump();
    expect(harness.host.tuneCalls, <(int, int)>[(7, 3)]);

    harness.host.completeTune(0, const TuneResult.success());
    await tester.pumpAndSettle();

    expect(find.byKey(ChannelsLandingKeys.recallProgress), findsNothing);
    expect(find.byKey(ChannelsLandingKeys.recallFeedback), findsOneWidget);
    expect(find.text('Tuned to CH 07 · 03.'), findsOneWidget);
  });

  testWidgets(
    'TASK-057: the current-channel card exposes an explicit button label, '
    'not just visible text a screen reader has to piece together',
    (WidgetTester tester) async {
      await pumpLanding(
        tester,
        radio: const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
          channel: 4,
          privacyCode: 8,
        ),
      );

      final Iterable<Semantics> candidates = tester
          .widgetList<Semantics>(
            find.descendant(
              of: find.byKey(ChannelsLandingKeys.currentCard),
              matching: find.byWidgetPredicate((w) => w is Semantics),
            ),
          )
          .where((s) => s.properties.label != null);
      expect(candidates, isNotEmpty);
      expect(
        candidates.any(
          (s) =>
              s.properties.label!.contains('CH 04') &&
              s.properties.label!.contains('open Talk'),
        ),
        isTrue,
      );
    },
  );

  test('no literal colour values in the landing (Design §3.2)', () {
    const List<String> paths = <String>[
      'lib/features/channels/channels_landing.dart',
      'lib/features/channels/channel_format.dart',
      'lib/features/channels/channel_memory.dart',
      'lib/features/channels/presentation_icons.dart',
    ];
    for (final String path in paths) {
      final String src = File(path).readAsStringSync();
      expect(src.contains('Color(0x'), isFalse, reason: path);
      expect(RegExp(r'\bColors\.').hasMatch(src), isFalse, reason: path);
    }
  });

  group('TASK-057 round 2 — responsive matrix + rendered guidelines', () {
    testWidgets('renders without exception across the full responsive matrix '
        '(320 lp, larger phone, landscape, text scale 2.0)', (tester) async {
      await expectResponsiveMatrix(tester, (t, size) async {
        // Fully unmount between cases: `pumpLanding` builds a fresh
        // harness (and thus a new `watchChannel` closure) each call,
        // which trips ChannelsLanding's own "same callback across
        // rebuilds" invariant if the previous tree is merely updated in
        // place rather than replaced.
        await t.pumpWidget(const SizedBox.shrink());
        await pumpLanding(t, surface: size);
      });
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(dark)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLanding(tester, brightness: Brightness.dark);
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(light)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpLanding(tester, brightness: Brightness.light);
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });
  });
}
