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

/// TASK-095 / V2-VT-030 group-detail fixture, dark and light. Same
/// loopback-server pattern as `test/features/groups/group_detail_golden_test.dart`
/// so the frozen regression copy exercises the real load path.
void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late GroupsController groupsController;
  late GroupDetailController controller;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    groupsController = GroupsController(
      directoryClient: directoryClient,
      repository: SharedPreferencesGroupsRepository(
        await SharedPreferences.getInstance(),
      ),
      keyPair: keyPair,
    );
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'id': 'g1',
        'name': 'Site crew',
        'key_version': 1,
        'members': [
          {'pk': 'me', 'callsign': 'Amy', 'role': 'admin', 'status': 'available'},
          {'pk': 'b', 'callsign': 'Bob', 'role': 'member', 'status': 'busy'},
          {'pk': 'c', 'callsign': 'Cara', 'role': 'member', 'status': 'offline'},
        ],
      },
    );
    controller = GroupDetailController(
      groupId: 'g1',
      groupsController: groupsController,
      directoryClient: directoryClient,
      keyPair: keyPair,
      myPk: 'me',
    );
  });

  tearDown(() async {
    await controller.dispose();
    await groupsController.dispose();
    directoryClient.close();
    await server.close();
  });

  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: GroupDetailScreen(
          controller: controller,
          myPk: 'me',
          groupSecret: const [],
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(GroupDetailScreen),
      matchesGoldenFile('goldens/groups_detail_$name.png'),
    );
  }

  testWidgets('Group detail (dark)', (tester) async {
    await pumpAndGolden(tester, name: 'dark', brightness: Brightness.dark);
  });

  testWidgets('Group detail (light)', (tester) async {
    await pumpAndGolden(tester, name: 'light', brightness: Brightness.light);
  });
}
