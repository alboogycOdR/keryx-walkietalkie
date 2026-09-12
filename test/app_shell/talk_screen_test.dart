import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/talk/talk_ptt_ring.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'fake_radio_host.dart';
import 'shell_harness.dart';

/// TASK-093 — the numbered-channel picker and Stations tab are both gone
/// (Design §1/§5): this shell-composed `TalkScreen` wrapper now only wires
/// `onAddContact`/`onCreateGroup` (the no-target empty-state affordances,
/// Design §2.1), backed by tab-switch callbacks the same way the R2 shell
/// wired `onSwitchToStations`.
void main() {
  late FakeRadioHost host;
  late int addContactCalls;
  late int createGroupCalls;

  Widget build() {
    host = FakeRadioHost();
    addContactCalls = 0;
    createGroupCalls = 0;
    return pumpShell(
      host: host,
      home: TalkScreen(
        host: host,
        onSwitchToContacts: () => addContactCalls++,
        onSwitchToGroups: () => createGroupCalls++,
      ),
    );
  }

  testWidgets('mounts TASK-051/092 TalkScreen with the TalkPttRing', (
    tester,
  ) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(ShellKeys.talk), findsOneWidget);
    expect(find.byType(talkui.TalkScreen), findsOneWidget);
    expect(find.byType(TalkPttRing), findsOneWidget);
  });

  testWidgets('no numbered-channel picker or Stations affordance is wired '
      '(v2 Design §1/§5)', (tester) async {
    givePhoneSurface(tester);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('keryx-talk-picker')), findsNothing);
    expect(find.byKey(const Key('keryx-talk-stations')), findsNothing);
    expect(find.byKey(const Key('keryx-talk-radio-controls')), findsNothing);
  });

  testWidgets(
    'the no-target empty state Add contact/Create group buttons switch '
    'tabs via the wired callbacks (Design §2.1)',
    (tester) async {
      givePhoneSurface(tester);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keryx-talk-add-contact')));
      await tester.pumpAndSettle();
      expect(addContactCalls, 1);

      await tester.tap(find.byKey(const Key('keryx-talk-create-group')));
      await tester.pumpAndSettle();
      expect(createGroupCalls, 1);
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
