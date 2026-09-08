import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart' show TunedChannel;
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/channels/channels_landing.dart';
import 'package:keryx/features/talk/talk_ptt_disc.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'fake_radio_host.dart';
import 'shell_harness.dart';

void main() {
  late FakeRadioHost host;

  Widget build() {
    host = FakeRadioHost();
    return pumpShell(host: host, home: const ChannelsScreen());
  }

  testWidgets('mounts TASK-049 ChannelsLanding with Open Talk and Select '
      'channel (UX-D01 / Design §2.1)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.channelsLanding), findsOneWidget);
    expect(find.byType(ChannelsLanding), findsOneWidget);
    expect(find.byKey(ChannelsLandingKeys.openTalk), findsOneWidget);
    expect(find.byKey(ChannelsLandingKeys.selectChannel), findsOneWidget);
    expect(find.byKey(ChannelsLandingKeys.recentSection), findsOneWidget);
    expect(find.text('Recent channels'), findsOneWidget);
    expect(find.byKey(ChannelsLandingKeys.emptyMemory), findsOneWidget);
  });

  testWidgets('renders real channel-recall memory from the host snapshot', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    host.emit(
      const RadioHostSnapshot(
        channelMemory: <TunedChannel>[TunedChannel(channel: 7, privacyCode: 3)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ChannelsLandingKeys.recentSection), findsOneWidget);
    expect(find.text('Recent channels'), findsOneWidget);
    expect(
      find.byKey(ChannelsLandingKeys.recentEntry(7, 3)),
      findsOneWidget,
    );
    expect(find.byKey(ChannelsLandingKeys.emptyMemory), findsNothing);

    await tester.tap(find.byKey(ChannelsLandingKeys.recentEntry(7, 3)));
    await tester.pumpAndSettle();

    expect(host.tuneCalls, <(int, int)>[(7, 3)]);
    // Recall retunes in place; it does not push Talk (Open Talk is a
    // separate affordance — Design §2.1).
    expect(find.byKey(ShellKeys.talk), findsNothing);
  });

  testWidgets('Open Talk pushes TASK-051 Talk without tuning', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
    await tester.pumpAndSettle();

    expect(host.tuneCalls, isEmpty);
    expect(find.byKey(ShellKeys.talk), findsOneWidget);
    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byType(TalkPttDisc), findsOneWidget);
  });

  testWidgets('Select channel pushes TASK-050 ChannelSelectorScreen', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ChannelsLandingKeys.selectChannel));
    await tester.tap(find.byKey(ChannelsLandingKeys.selectChannel));
    await tester.pumpAndSettle();

    expect(host.tuneCalls, isEmpty);
    expect(find.byKey(ShellKeys.channelSelector), findsOneWidget);
    expect(find.byType(ChannelSelectorScreen), findsOneWidget);
  });
}
