import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/channels/channels_landing.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_scan_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/settings/settings_screen.dart';
import 'package:keryx/features/stations/stations_screen.dart';
import 'package:keryx/features/talk/talk_ptt_disc.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'fake_radio_host.dart';
import 'shell_harness.dart';

/// TASK-052 — real Wave-4 screens in `MobileAppShell`: single host mounted
/// once above the navigator, Channels default / Settings persistent
/// (UX-D01/UX-D02), and navigation alone never touches a host lifecycle
/// method (VT-001).
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

  testWidgets('Channels is the default landing destination (UX-D01)', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.text('Channels'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(ChannelsLanding), findsOneWidget);
    expect(find.byKey(ShellKeys.channelsLanding), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('exactly two persistent destinations exist — no third for an '
      'unimplemented surface (UX-D01/UX-D02)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(2));
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Contacts'), findsNothing);
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
    'Channels -> Talk -> Settings -> Talk causes zero additional host '
    'start/dispose/tune calls (VT-001)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(host.startCalls, 1);

      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
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

  testWidgets('re-tapping the active destination pops its branch to root '
      'without touching the host', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
    await tester.pumpAndSettle();
    expect(find.byKey(ShellKeys.talk), findsOneWidget);

    await tester.tap(navDestination('Channels'));
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.talk), findsNothing);
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
    'switching Channels branch to a pushed Talk, then to Settings and back, '
    'preserves the Channels branch stack instead of disposing it '
    '(UX-FR-005/007 — Review round 1 finding 2)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      await tester.tap(navDestination('Settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.talk), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ShellKeys.talk),
        findsOneWidget,
        reason:
            'the Channels branch stack must survive a destination switch '
            '— Talk was pushed before switching away and must still be on '
            'top when switching back',
      );

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
    },
  );

  testWidgets(
    "KeryxUxTokens resolves non-null under the shell's real theme wiring "
    '(Review round 1 finding 1 — Technical §9 "final wiring")',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build(theme: keryxUxThemeData()));
      await tester.pumpAndSettle();

      final BuildContext context = tester.element(find.byType(NavigationBar));
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
    'each Wave-4 screen type is in the tree after the matching navigation',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(find.byType(ChannelsLanding), findsOneWidget);

      await tester.ensureVisible(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);
      expect(find.byKey(ShellKeys.channelSelector), findsOneWidget);
      await popScreen(tester, find.byType(ChannelSelectorScreen));

      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      expect(find.byType(talkui.TalkScreen), findsOneWidget);
      expect(find.byType(TalkPttDisc), findsOneWidget);

      await tester.tap(find.byKey(const Key('keryx-talk-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);
      await popScreen(tester, find.byType(ChannelSelectorScreen));

      await tester.tap(find.byKey(const Key('keryx-talk-stations')));
      await tester.pumpAndSettle();
      expect(find.byType(StationsScreen), findsOneWidget);
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

      await popScreen(tester, find.byType(StationsScreen));

      await tester.tap(find.byKey(const Key('keryx-talk-radio-controls')));
      await tester.pumpAndSettle();
      expect(find.byType(RadioControlsScreen), findsOneWidget);
      expect(find.byKey(ShellKeys.radioControls), findsOneWidget);
      await popScreen(tester, find.byType(RadioControlsScreen));

      await tester.tap(navDestination('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byKey(ShellKeys.settings), findsOneWidget);

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
      expect(host.tuneCalls, isEmpty);
    },
  );

  testWidgets(
    'pushed selector / Stations / Radio Controls survive a Channels↔Settings '
    'switch (IndexedStack branch preservation, VT-001)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keryx-talk-picker')));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);

      await tester.tap(navDestination('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(ChannelSelectorScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(
        find.byType(ChannelSelectorScreen),
        findsOneWidget,
        reason: 'selector must still be on the Channels stack after a tab switch',
      );

      await popScreen(tester, find.byType(ChannelSelectorScreen));
      expect(find.byKey(ShellKeys.talk), findsOneWidget);

      await tester.tap(find.byKey(const Key('keryx-talk-stations')));
      await tester.pumpAndSettle();
      expect(find.byType(StationsScreen), findsOneWidget);

      await tester.tap(navDestination('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(StationsScreen), findsOneWidget);

      await popScreen(tester, find.byType(StationsScreen));
      await tester.tap(find.byKey(const Key('keryx-talk-radio-controls')));
      await tester.pumpAndSettle();
      expect(find.byType(RadioControlsScreen), findsOneWidget);

      await tester.tap(navDestination('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(navDestination('Channels'));
      await tester.pumpAndSettle();
      expect(find.byType(RadioControlsScreen), findsOneWidget);

      expect(host.startCalls, 1);
      expect(host.disposeCalls, 0);
      expect(host.tuneCalls, isEmpty);
    },
  );

  test('new shell wiring does not import transport/floor/audio/platform APIs', () {
    const List<String> wiring = <String>[
      'lib/app_shell/channels_screen.dart',
      'lib/app_shell/talk_screen.dart',
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
