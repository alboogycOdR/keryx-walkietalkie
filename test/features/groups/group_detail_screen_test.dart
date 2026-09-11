import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/groups/group_detail_controller.dart';
import 'package:keryx/features/groups/group_detail_screen.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';

Widget _wrap(Widget child) => MaterialApp(theme: keryxUxThemeData(), home: child);

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late GroupsController groupsController;
  late String myPk;

  setUp(() async {
    // See `new_group_screen_test.dart`'s identical comment: this suite
    // talks to a real loopback `FakeDirectoryServer`, so the widget test
    // binding's `HttpOverrides` mock (400-for-everything) must be lifted.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    groupsController = GroupsController(
      directoryClient: directoryClient,
      repository: SharedPreferencesGroupsRepository(await SharedPreferences.getInstance()),
      keyPair: keyPair,
    );
  });

  tearDown(() async {
    await groupsController.dispose();
    directoryClient.close();
    await server.close();
  });

  // Note: `groupsController` itself is never subscribed-to from inside a
  // `runAsync` block in this suite (only `GroupDetailController`'s own
  // `_eventsSub` is), so `tearDown`'s plain `dispose()` is safe as-is —
  // see `controller.dispose()`'s own `runAsync` wrap above for the case
  // that actually needed it.

  testWidgets('admin controls are hidden entirely for a non-admin viewer', (tester) async {
    myPk = 'me';
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'id': 'g1',
        'name': 'Site crew',
        'key_version': 1,
        'members': [
          {'pk': 'me', 'callsign': 'ME', 'role': 'member', 'status': 'available'},
          {'pk': 'admin-pk', 'callsign': 'ADMIN', 'role': 'admin', 'status': 'available'},
        ],
      },
    );

    final controller = GroupDetailController(
      groupId: 'g1',
      groupsController: groupsController,
      directoryClient: directoryClient,
      keyPair: keyPair,
      myPk: myPk,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(GroupDetailScreen(controller: controller, myPk: myPk, groupSecret: const [])),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    // The rename/rotate-key actions are admin-only and must not exist in
    // the tree at all for a non-admin viewer (not just disabled).
    expect(find.byKey(const Key('group-detail.rename')), findsNothing);
    expect(find.byKey(const Key('group-detail.rotate-key')), findsNothing);
    // Leave is always available.
    expect(find.byKey(const Key('group-detail.leave')), findsOneWidget);

    await tester.runAsync(() => controller.dispose());
  });

  testWidgets('admin controls are shown for an admin viewer', (tester) async {
    myPk = 'me';
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'id': 'g1',
        'name': 'Site crew',
        'key_version': 1,
        'members': [
          {'pk': 'me', 'callsign': 'ME', 'role': 'admin', 'status': 'available'},
        ],
      },
    );

    final controller = GroupDetailController(
      groupId: 'g1',
      groupsController: groupsController,
      directoryClient: directoryClient,
      keyPair: keyPair,
      myPk: myPk,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(GroupDetailScreen(controller: controller, myPk: myPk, groupSecret: const [])),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.byKey(const Key('group-detail.rename')), findsOneWidget);
    expect(find.byKey(const Key('group-detail.rotate-key')), findsOneWidget);

    await tester.runAsync(() => controller.dispose());
  });

  // A third widget-level test ("a key-rotation toast is surfaced live on
  // the screen") was attempted here and dropped: `testWidgets`'
  // fake-async zone plus a `GroupsController.rotate` call that triggers a
  // *second*, unawaited, reactive `GroupDetailController.load()` (a
  // second real HTTP round-trip fired from inside a sync stream-event
  // callback) reliably deadlocks flutter_test's timer bookkeeping no
  // matter how the `runAsync`/await shape is arranged — a framework
  // interaction, not a product bug. The identical behaviour (toast copy,
  // triggered by `GroupsController.rotate`, including the reactive
  // reload) is already exercised at the controller level in
  // `group_detail_controller_test.dart`'s "key rotation notice via
  // GroupsController.events surfaces a toast and reloads" test, which
  // runs in a plain `test()` with no fake-async zone and passes cleanly.
}
