import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart' show TunedChannel;
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/channels/channels_landing.dart';

import 'fake_radio_host.dart';
import 'shell_harness.dart';

/// TASK-077 (ADR-002 §2 O2, §3 A1) — `ChannelsScreen` is now the Channels
/// **tab** body, not a pushed screen with its own Open Talk button: Talk is
/// a sibling tab, so `embedded:true` and no `onOpenTalk`. What replaces it
/// is the "switch to Talk" signal a successful tune produces (recall here,
/// or a selector opened from here — see `mobile_app_shell_test.dart` for
/// the selector-apply half, which needs the full shell to observe
/// `radioStateProvider`).
void main() {
  late FakeRadioHost host;
  late int switchToTalkCalls;

  Widget build() {
    host = FakeRadioHost();
    switchToTalkCalls = 0;
    return pumpShell(
      host: host,
      home: ChannelsScreen(onSwitchToTalk: () => switchToTalkCalls++),
    );
  }

  testWidgets('mounts TASK-049 ChannelsLanding embedded, with Select '
      'channel but no Open Talk button (ADR-002 §3 A1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.channelsLanding), findsOneWidget);
    expect(find.byType(ChannelsLanding), findsOneWidget);
    expect(
      find.byKey(ChannelsLandingKeys.openTalk),
      findsNothing,
      reason: 'Talk is a sibling tab now, not pushed from here',
    );
    expect(find.byKey(ChannelsLandingKeys.selectChannel), findsOneWidget);
    expect(find.byKey(ChannelsLandingKeys.recentSection), findsOneWidget);
    expect(find.text('Recent channels'), findsOneWidget);
    expect(find.byKey(ChannelsLandingKeys.emptyMemory), findsOneWidget);
    expect(
      find.byType(AppBar),
      findsNothing,
      reason: 'embedded:true omits the standalone app bar — the shell '
          'owns it',
    );
  });

  testWidgets(
    'a successful channel-recall retune calls onSwitchToTalk (ADR-002 §3 '
    'A1: "Channels recall success … switch to Talk")',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      host.emit(
        const RadioHostSnapshot(
          channelMemory: <TunedChannel>[TunedChannel(channel: 7, privacyCode: 3)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)), findsOneWidget);

      await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
      await tester.pumpAndSettle();

      expect(host.tuneCalls, <(int, int)>[(7, 3)]);
      expect(
        switchToTalkCalls,
        1,
        reason: 'FakeRadioHost.tune() resolves success, which must reach '
            'onSwitchToTalk exactly once',
      );
    },
  );

  testWidgets('Select channel pushes TASK-050 ChannelSelectorScreen, wired '
      'so a successful apply also calls onSwitchToTalk', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ChannelsLandingKeys.selectChannel));
    await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
    await tester.pumpAndSettle();

    expect(host.tuneCalls, isEmpty);
    expect(find.byKey(ShellKeys.channelSelector), findsOneWidget);
    expect(find.byType(ChannelSelectorScreen), findsOneWidget);
    expect(
      switchToTalkCalls,
      0,
      reason: 'no retune has happened yet — onSwitchToTalk is not called '
          'just from opening the selector',
    );
  });
}
