import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/groups/group_view_models.dart';
import 'package:keryx/features/groups/groups_list_screen.dart';

/// TASK-091 — golden fixtures for the Groups tab: empty/populated, dark and
/// light (mirrors `test/regression/goldens/channels_golden_test.dart`'s own
/// pattern), kept under this task's own `test/features/groups/goldens/**`
/// rather than the shared `test/regression/goldens/**` tree.
void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required List<GroupListRow> rows,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: GroupsListScreen(rows: rows),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(GroupsListScreen),
      matchesGoldenFile('goldens/groups_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Groups — empty ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: 'empty_$suffix', brightness: brightness, rows: const []);
    });

    testWidgets('Groups — populated ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'populated_$suffix',
        brightness: brightness,
        rows: const [
          GroupListRow(id: 'g1', name: 'Site crew', onlineCount: 4, totalCount: 12, isAdmin: true),
          GroupListRow(id: 'g2', name: 'Weekend', onlineCount: 0, totalCount: 2, isAdmin: false),
        ],
      );
    });
  }
}
