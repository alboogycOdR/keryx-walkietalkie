import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart' hide StationsScreen;
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/talk/talk_ptt_ring.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'fake_radio_host.dart';
import 'shell_harness.dart';

/// TASK-077 (ADR-002 §3 A1/A2) — the Stations header affordance now
/// switches the shell to the Stations tab instead of pushing a screen, and
/// Radio controls moved to the app bar's overflow menu, so this wrapper no
/// longer wires `onOpenRadioControls` at all (the feature `TalkScreen`
/// renders that button only when non-null).
void main() {
  late FakeRadioHost host;
  late int switchToStationsCalls;

  Widget build() {
    host = FakeRadioHost();
    switchToStationsCalls = 0;
    return pumpShell(
      host: host,
      home: TalkScreen(
        host: host,
        onSwitchToStations: () => switchToStationsCalls++,
      ),
    );
  }

  testWidgets('mounts TASK-051 TalkScreen with the ADR-002 TalkPttRing '
      '(TASK-074)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.talk), findsOneWidget);
    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byType(TalkPttRing), findsOneWidget);
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
    "stations' real onOpenStations callback switches to the Stations tab "
    'instead of pushing a screen (ADR-002 §3 A1)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keryx-talk-stations')));
      await tester.pumpAndSettle();

      expect(switchToStationsCalls, 1);
    },
  );

  testWidgets(
    'Radio Controls header button is absent — that affordance moved to '
    "the app bar's overflow menu (ADR-002 §3 A2: rendered only when "
    'non-null, and this wrapper never wires it)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('keryx-talk-radio-controls')),
        findsNothing,
      );
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
