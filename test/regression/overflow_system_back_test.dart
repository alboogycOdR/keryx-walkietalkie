import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/features/channels/channels_landing.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/settings/settings_screen.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'regression_shell_harness.dart';

/// TASK-078 — carried from TASK-077 review (non-blocking (b)): real Android
/// system back (`tester.binding.handlePopRoute()`, never `Navigator.pop`)
/// from the overflow Settings and Radio controls routes must keep the
/// previous tab (ADR-002 A1).
void main() {
  testWidgets(
    'system back from overflow Settings keeps the previous tab '
    '(ADR-002 A1; TASK-077 review carry)',
    (tester) async {
      await pumpRegressionShell(tester);

      await tester.tap(tabChannels());
      await tester.pumpAndSettle();
      expect(find.byType(ChannelsLanding), findsOneWidget);

      await tester.tap(overflowMenu());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShellKeys.overflowSettings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      final bool popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        popped,
        isTrue,
        reason: 'system back on overflow Settings must be claimed',
      );
      expect(find.byType(SettingsScreen), findsNothing);
      expect(
        find.byType(ChannelsLanding),
        findsOneWidget,
        reason: 'returning from overflow Settings must keep the Channels tab',
      );
      expect(find.byType(talkui.TalkScreen), findsNothing);
    },
  );

  testWidgets(
    'system back from overflow Radio controls keeps the previous tab '
    '(ADR-002 A1; TASK-077 review carry)',
    (tester) async {
      await pumpRegressionShell(tester);

      await tester.tap(tabStations());
      await tester.pumpAndSettle();

      await tester.tap(overflowMenu());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShellKeys.overflowRadioControls));
      await tester.pumpAndSettle();
      expect(find.byType(RadioControlsScreen), findsOneWidget);

      final bool popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        popped,
        isTrue,
        reason: 'system back on overflow Radio controls must be claimed',
      );
      expect(find.byType(RadioControlsScreen), findsNothing);
      expect(
        find.byKey(ShellKeys.stations),
        findsOneWidget,
        reason: 'returning from overflow Radio controls must keep Stations',
      );
      expect(find.byType(talkui.TalkScreen), findsNothing);
    },
  );
}
