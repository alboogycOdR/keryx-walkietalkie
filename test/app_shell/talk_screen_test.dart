import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/stations/stations_screen.dart';
import 'package:keryx/features/talk/talk_ptt_disc.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'fake_radio_host.dart';
import 'shell_harness.dart';

void main() {
  late FakeRadioHost host;

  Widget build() {
    host = FakeRadioHost();
    return pumpShell(host: host, home: TalkScreen(host: host));
  }

  testWidgets('mounts TASK-051 TalkScreen with TalkPttDisc', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.talk), findsOneWidget);
    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byType(TalkPttDisc), findsOneWidget);
  });

  testWidgets(
    "picker's real onOpenPicker callback pushes TASK-050 "
    'ChannelSelectorScreen (TASK-068 — no overlay involved)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keryx-talk-picker')));
      await tester.pumpAndSettle();

      expect(find.byKey(ShellKeys.channelSelector), findsOneWidget);
      expect(find.byType(ChannelSelectorScreen), findsOneWidget);
    },
  );

  testWidgets(
    "stations' real onOpenStations callback pushes TASK-053 "
    'StationsScreen (TASK-068 — no overlay involved)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keryx-talk-stations')));
      await tester.pumpAndSettle();

      expect(find.byKey(ShellKeys.stations), findsOneWidget);
      expect(find.byType(StationsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Radio Controls header button pushes TASK-054 RadioControlsScreen '
    '(TASK-068 — real header slot, not a bottom-left shell overlay)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keryx-talk-radio-controls')));
      await tester.pumpAndSettle();

      expect(find.byKey(ShellKeys.radioControls), findsOneWidget);
      expect(find.byType(RadioControlsScreen), findsOneWidget);
    },
  );

  testWidgets('a pending mic-permission fault projects as an overlay cue, '
      'not a fabricated full-strength signal', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    host.emit(const RadioHostSnapshot(micPermissionDenied: true));
    await tester.pumpAndSettle();

    expect(find.text('Microphone required'), findsOneWidget);
  });
}
