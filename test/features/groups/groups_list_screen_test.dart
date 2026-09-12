import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/groups/group_view_models.dart';
import 'package:keryx/features/groups/groups_copy.dart';
import 'package:keryx/features/groups/groups_list_screen.dart';

Widget _wrap(Widget child) => MaterialApp(theme: keryxUxThemeData(), home: child);

void main() {
  testWidgets('renders the empty state when there are no groups', (tester) async {
    await tester.pumpWidget(_wrap(const GroupsListScreen(rows: [])));
    expect(find.byKey(const Key('keryx-groups-empty')), findsOneWidget);
    expect(find.text(GroupsCopy.emptyStateTitle), findsOneWidget);
  });

  testWidgets('renders one row per group with the member count label', (tester) async {
    const rows = [
      GroupListRow(id: 'g1', name: 'Site crew', onlineCount: 4, totalCount: 12, isAdmin: true),
      GroupListRow(id: 'g2', name: 'Weekend', onlineCount: 0, totalCount: 2, isAdmin: false),
    ];
    await tester.pumpWidget(_wrap(const GroupsListScreen(rows: rows)));

    expect(find.text('Site crew'), findsOneWidget);
    expect(find.text(GroupsCopy.memberCountLabel(online: 4, total: 12)), findsOneWidget);
    expect(find.text(GroupsCopy.memberCountLabel(online: 0, total: 2)), findsOneWidget);
  });

  testWidgets('row tap calls onSelectTarget with that row', (tester) async {
    GroupListRow? selected;
    const row = GroupListRow(id: 'g1', name: 'Site crew', onlineCount: 1, totalCount: 2, isAdmin: false);
    await tester.pumpWidget(
      _wrap(GroupsListScreen(rows: const [row], onSelectTarget: (r) => selected = r)),
    );

    await tester.tap(find.text('Site crew'));
    await tester.pump();

    expect(selected?.id, 'g1');
  });

  testWidgets('chevron tap calls onOpenDetail without also selecting', (tester) async {
    GroupListRow? opened;
    GroupListRow? selected;
    const row = GroupListRow(id: 'g1', name: 'Site crew', onlineCount: 1, totalCount: 2, isAdmin: false);
    await tester.pumpWidget(
      _wrap(
        GroupsListScreen(
          rows: const [row],
          onSelectTarget: (r) => selected = r,
          onOpenDetail: (r) => opened = r,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-groups-row-chevron-g1')));
    await tester.pump();

    expect(opened?.id, 'g1');
    expect(selected, isNull);
  });

  testWidgets('New group and Join with a code floating actions fire their callbacks', (tester) async {
    var newGroupTapped = false;
    var joinTapped = false;
    await tester.pumpWidget(
      _wrap(
        GroupsListScreen(
          rows: const [],
          onNewGroup: () => newGroupTapped = true,
          onJoinWithCode: () => joinTapped = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-groups-new')));
    await tester.tap(find.byKey(const Key('keryx-groups-join-with-code')));

    expect(newGroupTapped, isTrue);
    expect(joinTapped, isTrue);
  });
}
