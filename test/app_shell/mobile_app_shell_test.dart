import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart' hide StationsScreen;
import 'package:keryx/core/radio_host/radio_host_snapshot.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/channels/channels_landing.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_scan_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/settings/settings_screen.dart';
import 'package:keryx/features/stations/stations_screen.dart';
import 'package:keryx/features/talk/talk_ptt_ring.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'fake_radio_host.dart';
import 'shell_harness.dart';

/// Test-only seam so a test can drive `radioStateProvider` directly —
/// mirrors `test/features/channels/channels_landing_test.dart`'s own
/// `SeededRadioStateController` (private to that file; duplicated rather
/// than imported since importing another test file as a library is not
/// this codebase's convention).
class _SeededRadioStateController extends RadioStateController {
  _SeededRadioStateController(this._seed);

  final RadioState _seed;

  @override
  RadioState build() => _seed;
}

/// TASK-077 (ADR-002 §2/§3) — the R2 shell: Talk is the default tab, a top
/// app bar carries the wordmark/connection indicator/overflow menu, and an
/// icon-only tab strip (Talk · Channels · Stations) replaces the old bottom
/// `NavigationBar`. The single host is still mounted once above every
/// route, and navigation alone never touches a host lifecycle method
/// (VT-001).
void main() {
  late FakeRadioHost host;

  Widget build({ThemeData? theme}) {
    host = FakeRadioHost();
    return pumpShell(
      host: host,
      home: const MobileAppShell(),
      theme: theme,
    );
  }

  testWidgets('Talk is the default landing destination on every launch '
      '(ADR-002 §2 O1) — no picker is shown', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byKey(ShellKeys.talk), findsOneWidget);
    expect(find.byType(ChannelsLanding), findsNothing);
    expect(find.byType(ChannelSelectorScreen), findsNothing);
  });

  testWidgets('exactly three tab strip destinations exist, no bottom '
      'NavigationBar (ADR-002 §3 A1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(ShellKeys.tabTalk), findsOneWidget);
    expect(find.byKey(ShellKeys.tabChannels), findsOneWidget);
    expect(find.byKey(ShellKeys.tabStations), findsOneWidget);
  });

  testWidgets('each tab target meets the 48 dp minimum and carries a '
      'semantic label (ADR-002 §3 A1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    for (final (Key key, String label) in <(Key, String)>[
      (ShellKeys.tabTalk, 'Talk'),
      (ShellKeys.tabChannels, 'Channels'),
      (ShellKeys.tabStations, 'Stations'),
    ]) {
      final Size size = tester.getSize(find.byKey(key));
      expect(
        size.height,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
        reason: '$label tab must meet the 48 dp target',
      );
      expect(
        find.bySemanticsLabel(label),
        findsWidgets,
        reason: '$label tab must expose a semantic label',
      );
    }
  });

  testWidgets('the host is constructed and started exactly once on mount', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets(
    'Talk -> Channels -> Stations -> Talk causes zero additional host '
    'start/dispose/tune calls (VT-001)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(host.startCalls, 1);
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelsLanding), findsOneWidget);

      await tester.tap(navDestination('Stations'));
      await tester.pumpAndSettle();
      expect(find.byType(StationsScreen), findsOneWidget);

      await tester.tap(navDestination('Talk'));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      expect(
        host.startCalls,
        1,
        reason: 'navigation must never re-start the host',
      );
      expect(
        host.disposeCalls,
        0,
        reason: 'navigation must never dispose the host',
      );
      expect(
        host.tuneCalls,
        isEmpty,
        reason: 'navigation alone must never retune',
      );
    },
  );

  testWidgets('re-tapping the active tab pops its branch to root '
      'without touching the host', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(navDestination('Channels'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ChannelsLandingKeys.selectChannel));
    await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelSelectorScreen), findsOneWidget);

    await tester.tap(navDestination('Channels'));
    await tester.pumpAndSettle();

    expect(find.byType(ChannelSelectorScreen), findsNothing);
    expect(find.byType(ChannelsLanding), findsOneWidget);
    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets(
    'a horizontal drag across the Talk body, including across the PTT, '
    'never changes the active tab (ADR-002 §3 A1)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      final Finder ptt = find.byKey(const Key('keryx-talk-ptt-disc'));
      await tester.drag(ptt, const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(
        find.byKey(ShellKeys.talk),
        findsOneWidget,
        reason: 'a swipe must never be interpreted as a tab change — there '
            'is no PageView/TabBarView anywhere in this shell',
      );
      expect(find.byType(ChannelsLanding), findsNothing);
      expect(find.byType(StationsScreen), findsNothing);
    },
  );

  testWidgets(
    'system back on the Channels tab root returns to Talk; on the Talk '
    'root it falls through to the platform (ADR-002 §3 A1)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelsLanding), findsOneWidget);

      final bool poppedFromChannels = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        poppedFromChannels,
        isTrue,
        reason: 'the shell itself must intercept back on a non-Talk tab '
            'root rather than letting it propagate to the platform',
      );
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      final bool poppedFromTalk = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        poppedFromTalk,
        isFalse,
        reason: 'back on the Talk root must fall through to the platform',
      );
    },
  );

  testWidgets(
    'a pushed screen on the active branch pops via its own Navigator, '
    'independent of the Talk-return PopScope one level up',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Stations'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(StationsScreenKeys.export));
      await tester.pumpAndSettle();
      expect(find.byType(EventQrUiExportScreen), findsOneWidget);

      await popScreen(tester, find.byType(EventQrUiExportScreen));
      expect(
        find.byType(StationsScreen),
        findsOneWidget,
        reason: 'the pushed Event QR export screen pops back to the '
            'Stations branch root, not to Talk',
      );
    },
  );

  group('real Android system back (tester.binding.handlePopRoute)', () {
    // Round-1 rework finding: `popScreen` above calls `Navigator.pop`
    // directly, which only proves the branch's own Navigator *can* pop —
    // it never proves the platform back button actually reaches it. These
    // four use the real `handlePopRoute()` dispatch path instead.

    testWidgets(
      'Talk -> picker -> back closes the picker, stays on Talk, and the '
      'shell reports it handled the pop',
      (tester) async {
        givePhoneSurface(tester);
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('keryx-talk-picker')));
        await tester.pumpAndSettle();
        expect(find.byType(ChannelSelectorScreen), findsOneWidget);

        final bool popped = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(
          popped,
          isTrue,
          reason: 'system back on a screen pushed inside the Talk branch '
              'must be consumed by that branch, not fall through and '
              'background/close the app',
        );
        expect(find.byType(ChannelSelectorScreen), findsNothing);
        expect(find.byKey(ShellKeys.talk), findsOneWidget);
      },
    );

    testWidgets(
      'Stations -> Export -> back returns to the Stations root, not Talk',
      (tester) async {
        givePhoneSurface(tester);
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.tap(navDestination('Stations'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(StationsScreenKeys.export));
        await tester.pumpAndSettle();
        expect(find.byType(EventQrUiExportScreen), findsOneWidget);

        final bool popped = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(popped, isTrue);
        expect(find.byType(EventQrUiExportScreen), findsNothing);
        expect(
          find.byType(StationsScreen),
          findsOneWidget,
          reason: 'back must pop the Export screen off the Stations '
              'branch, not switch the shell to Talk',
        );
      },
    );

    testWidgets(
      'Channels -> selector -> back returns to the Channels root',
      (tester) async {
        givePhoneSurface(tester);
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.tap(navDestination('Channels'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(ChannelsLandingKeys.selectChannel),
        );
        await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
        await tester.pumpAndSettle();
        expect(find.byType(ChannelSelectorScreen), findsOneWidget);

        final bool popped = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(popped, isTrue);
        expect(find.byType(ChannelSelectorScreen), findsNothing);
        expect(find.byType(ChannelsLanding), findsOneWidget);
      },
    );

    testWidgets(
      'root cases still hold: Channels root -> Talk; Talk root -> platform',
      (tester) async {
        givePhoneSurface(tester);
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.tap(navDestination('Channels'));
        await tester.pumpAndSettle();

        final bool poppedFromChannels = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(poppedFromChannels, isTrue);
        expect(find.byKey(ShellKeys.talk), findsOneWidget);

        final bool poppedFromTalk = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(poppedFromTalk, isFalse);
      },
    );
  });

  testWidgets('overflow menu opens Radio controls and Settings full-screen '
      'with back; returning keeps the current tab and channel', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(navDestination('Channels'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ShellKeys.overflowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ShellKeys.overflowRadioControls));
    await tester.pumpAndSettle();
    expect(find.byType(RadioControlsScreen), findsOneWidget);
    expect(find.byKey(ShellKeys.radioControls), findsOneWidget);
    await popScreen(tester, find.byType(RadioControlsScreen));
    expect(
      find.byType(ChannelsLanding),
      findsOneWidget,
      reason: 'returning from the overflow route keeps the Channels tab',
    );

    await tester.tap(find.byKey(ShellKeys.overflowMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ShellKeys.overflowSettings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(ShellKeys.settings), findsOneWidget);
    await popScreen(tester, find.byType(SettingsScreen));
    expect(find.byType(ChannelsLanding), findsOneWidget);

    expect(host.startCalls, 1);
    expect(host.disposeCalls, 0);
  });

  testWidgets('legacy face route is not linked from any shell destination', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byTooltip(legacyFaceRouteName), findsNothing);
    expect(find.text(legacyFaceRouteName), findsNothing);
  });

  testWidgets(
    'switching Channels branch to a pushed selector, then to Stations and '
    'back, preserves the Channels branch stack instead of disposing it '
    '(UX-FR-005/007)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);

      await tester.tap(navDestination('Stations'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsNothing);
      expect(find.byType(StationsScreen), findsOneWidget);

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(
        find.byType(ChannelSelectorScreen),
        findsOneWidget,
        reason:
            'the Channels branch stack must survive a tab switch — the '
            'selector was pushed before switching away and must still be '
            'on top when switching back',
      );

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
    },
  );

  testWidgets(
    "KeryxUxTokens resolves non-null under the shell's real theme wiring "
    '(Technical §9 "final wiring")',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(AppBar));
      final KeryxUxTokens? tokens = Theme.of(
        context,
      ).extension<KeryxUxTokens>();
      expect(tokens, isNotNull);
      expect(
        tokens!.brightness,
        Brightness.dark,
        reason: 'dark is the default theme (Design §3.1)',
      );
      expect(tokens.palette.surfaceBase, KeryxUxPalette.dark.surfaceBase);
    },
  );

  testWidgets(
    'each destination is reachable and stays wired end to end: Talk picker '
    '-> selector, Talk station chip -> Stations tab, Stations Export/Scan',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(find.byType(talkui.TalkScreen), findsOneWidget);
      expect(find.byType(TalkPttRing), findsOneWidget);

      await tester.tap(find.byKey(const Key('keryx-talk-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);
      expect(find.byKey(ShellKeys.channelSelector), findsOneWidget);
      await popScreen(tester, find.byType(ChannelSelectorScreen));

      await tester.tap(find.byKey(const Key('keryx-talk-stations')));
      await tester.pumpAndSettle();
      expect(
        find.byType(StationsScreen),
        findsOneWidget,
        reason: 'the station chip switches to the Stations tab, it no '
            'longer pushes a screen (ADR-002 §3 A1)',
      );
      expect(find.byKey(ShellKeys.stations), findsOneWidget);

      await tester.tap(find.byKey(StationsScreenKeys.export));
      await tester.pumpAndSettle();
      expect(find.byType(EventQrUiExportScreen), findsOneWidget);
      expect(find.byKey(ShellKeys.eventQrExport), findsOneWidget);
      await popScreen(tester, find.byType(EventQrUiExportScreen));

      await tester.tap(find.byKey(StationsScreenKeys.scan));
      await tester.pump();
      await tester.pump();
      expect(find.byType(EventQrUiScanScreen), findsOneWidget);
      expect(find.byKey(ShellKeys.eventQrScan), findsOneWidget);
      await popScreen(tester, find.byType(EventQrUiScanScreen), settle: false);

      await tester.tap(navDestination('Talk'));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
      expect(host.tuneCalls, isEmpty);
    },
  );

  testWidgets(
    'a successful recent-channel recall on the Channels tab switches to '
    'Talk (ADR-002 §3 A1: "Channels recall success … switch to Talk")',
    (tester) async {
      givePhoneSurface(tester);
      host = FakeRadioHost();
      host.emit(
        const RadioHostSnapshot(
          channelMemory: <TunedChannel>[
            TunedChannel(channel: 5, privacyCode: 10),
          ],
        ),
      );
      await tester.pumpWidget(
        pumpShell(host: host, home: const MobileAppShell()),
      );
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelsLanding), findsOneWidget);

      await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(5, 10)));
      // FakeRadioHost.tune() resolves TuneResult.success() synchronously
      // once the microtask/timer queue drains.
      await tester.pumpAndSettle();

      expect(
        find.byKey(ShellKeys.talk),
        findsOneWidget,
        reason: 'a successful recall must switch the shell to the Talk tab',
      );
      expect(host.tuneCalls, contains((5, 10)));
    },
  );

  testWidgets(
    'a selector opened from the Channels tab switches to Talk once '
    'RadioState actually retunes (ADR-002 §3 A1: "selector apply switch '
    'to Talk")',
    (tester) async {
      givePhoneSurface(tester);
      host = FakeRadioHost();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          radioStateProvider.overrideWith(
            () => _SeededRadioStateController(
              const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: keryxUxThemeData(),
            home: const MobileAppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);

      // The real, host-confirmed signal a tune took effect — not the
      // selector's own private outcome stream (Owned_Paths for this task
      // does not include `channel_selector_screen.dart`).
      container
          .read(radioStateProvider.notifier)
          .dispatch(const TuneTo(channel: 7, privacyCode: 3));
      await tester.pumpAndSettle();

      expect(find.byType(ChannelSelectorScreen), findsNothing);
      expect(
        find.byKey(ShellKeys.talk),
        findsOneWidget,
        reason: 'a selector apply that actually retuned must auto-return '
            'to Talk',
      );
    },
  );

  testWidgets(
    'a selector opened from Talk itself does not auto-return — only the '
    'Channels-opened selector carries that behaviour',
    (tester) async {
      givePhoneSurface(tester);
      host = FakeRadioHost();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          radioStateProvider.overrideWith(
            () => _SeededRadioStateController(
              const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: keryxUxThemeData(),
            home: const MobileAppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      await tester.tap(find.byKey(const Key('keryx-talk-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);

      container
          .read(radioStateProvider.notifier)
          .dispatch(const TuneTo(channel: 8, privacyCode: 4));
      await tester.pumpAndSettle();

      expect(
        find.byType(ChannelSelectorScreen),
        findsOneWidget,
        reason: 'the Talk-opened selector must stay open until Cancel/back '
            '— it never had an onApplied callback wired',
      );
    },
  );

  group('connection indicator dot colour (ADR-002 §3 A1 "healthy vs '
      'degraded")', () {
    // Round-1 rework finding: healthy (`actionPrimary`) and degraded
    // (`stateWarning`) were ~8° apart in hue and effectively
    // indistinguishable at 10 dp, so the dot carried no cue at all. These
    // assert the three states now resolve to visibly distinct tokens.

    Future<Color> pumpAndReadDotColor(
      WidgetTester tester,
      RadioState seed,
    ) async {
      givePhoneSurface(tester);
      final FakeRadioHost seededHost = FakeRadioHost();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(seededHost),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          radioStateProvider.overrideWith(
            () => _SeededRadioStateController(seed),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: keryxUxThemeData(),
            home: const MobileAppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Container dot = tester.widget<Container>(
        find.descendant(
          of: find.byKey(ShellKeys.connectionIndicator),
          matching: find.byType(Container),
        ),
      );
      return (dot.decoration! as BoxDecoration).color!;
    }

    final KeryxUxTokens tokens = keryxUxThemeData().extension<KeryxUxTokens>()!;

    testWidgets('healthy resolves to stateRx and is labelled healthy', (
      tester,
    ) async {
      final Color color = await pumpAndReadDotColor(
        tester,
        const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
          isNoLink: false,
        ),
      );
      expect(color, tokens.stateRx);
      expect(
        find.bySemanticsLabel(RegExp('Connection healthy')),
        findsOneWidget,
      );
    });

    testWidgets('degraded resolves to stateWarning, distinct from healthy', (
      tester,
    ) async {
      final Color color = await pumpAndReadDotColor(
        tester,
        const RadioState(
          phase: RadioPhase.linkDegraded,
          mode: RadioMode.local,
          isNoLink: false,
        ),
      );
      expect(color, tokens.stateWarning);
      expect(color, isNot(tokens.stateRx));
      expect(
        find.bySemanticsLabel(RegExp('Connection degraded')),
        findsOneWidget,
      );
    });

    testWidgets(
      'unresolved/connecting resolves to pttNeutralRing, distinct from '
      'both healthy and degraded',
      (tester) async {
        final Color color = await pumpAndReadDotColor(
          tester,
          const RadioState(
            phase: RadioPhase.idle,
            mode: RadioMode.auto,
            isNoLink: false,
          ),
        );
        expect(color, tokens.pttNeutralRing);
        expect(color, isNot(tokens.stateRx));
        expect(color, isNot(tokens.stateWarning));
        expect(
          find.bySemanticsLabel(RegExp('Connection connecting')),
          findsOneWidget,
        );
      },
    );
  });

  test('new shell wiring does not import transport/floor/audio/platform APIs', () {
    const List<String> wiring = <String>[
      'lib/app_shell/channels_screen.dart',
      'lib/app_shell/talk_screen.dart',
      'lib/app_shell/stations_screen.dart',
      'lib/app_shell/shell_routes.dart',
      'lib/app_shell/shell_keys.dart',
      'lib/app_shell/mobile_app_shell.dart',
      'lib/app_shell/app_shell.dart',
    ];
    const List<String> banned = <String>[
      'package:keryx/core/audio',
      'package:keryx/core/floor',
      'package:keryx/services/mesh',
      'package:keryx/services/linked',
      'package:keryx/services/platform',
    ];
    for (final String path in wiring) {
      final String source = File(path).readAsStringSync();
      for (final String needle in banned) {
        expect(
          source.contains(needle),
          isFalse,
          reason: '$path must not import $needle (Technical §5.1)',
        );
      }
    }
  });
}
