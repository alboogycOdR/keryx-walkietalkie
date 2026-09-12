import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/features/my_code/my_code_screen.dart';
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

      await tester.tap(tabContacts());
      await tester.pumpAndSettle();
      expect(find.byType(ContactsTabScreen), findsOneWidget);

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
        find.byType(ContactsTabScreen),
        findsOneWidget,
        reason: 'returning from overflow Settings must keep the Contacts tab',
      );
      expect(find.byType(talkui.TalkScreen), findsNothing);
    },
  );

  testWidgets(
    'system back from overflow Radio controls keeps the previous tab '
    '(ADR-002 A1; TASK-077 review carry)',
    (tester) async {
      await pumpRegressionShell(tester);

      await tester.tap(tabGroups());
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
        find.byType(GroupsTabScreen),
        findsOneWidget,
        reason: 'returning from overflow Radio controls must keep Groups',
      );
      expect(find.byType(talkui.TalkScreen), findsNothing);
    },
  );

  testWidgets(
    'system back from overflow My code keeps the previous tab '
    '(V2-VT-029; Design §1)',
    (tester) async {
      await pumpRegressionShell(tester);

      await tester.tap(tabTalk());
      await tester.pumpAndSettle();
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      await tester.tap(overflowMenu());
      await tester.pumpAndSettle();
      expect(find.byKey(ShellKeys.overflowMyCode), findsOneWidget);
      await tester.tap(find.byKey(ShellKeys.overflowMyCode));
      await tester.pumpAndSettle();
      expect(find.byType(MyCodeScreen), findsOneWidget);

      final bool popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        popped,
        isTrue,
        reason: 'system back on overflow My code must be claimed',
      );
      expect(find.byType(MyCodeScreen), findsNothing);
      expect(
        find.byType(talkui.TalkScreen),
        findsOneWidget,
        reason: 'returning from overflow My code must keep the Talk tab',
      );
    },
  );
}
