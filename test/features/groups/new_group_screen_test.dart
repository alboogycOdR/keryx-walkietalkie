import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/groups/new_group_screen.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';

Widget _wrap(Widget child) => MaterialApp(theme: keryxUxThemeData(), home: child);

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late GroupsController groupsController;

  setUp(() async {
    // `TestWidgetsFlutterBinding` installs a global `HttpOverrides` mock
    // that makes every `HttpClient` request return 400 without hitting the
    // network — real, necessary for most widget tests, but this suite
    // deliberately talks to a real loopback `FakeDirectoryServer` via
    // `DirectoryClient`'s `dart:io HttpClient`, so the mock must be lifted.
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

  testWidgets('an empty name shows an inline error and never calls createGroup', (tester) async {
    await tester.pumpWidget(
      _wrap(NewGroupScreen(groupsController: groupsController, onCreated: (_) {})),
    );

    await tester.tap(find.byKey(const Key('keryx-new-group-create')));
    await tester.pump();

    expect(find.text('Enter a group name.'), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('a valid name creates the group and calls onCreated', (tester) async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});
    dynamic created;

    await tester.pumpWidget(
      _wrap(NewGroupScreen(groupsController: groupsController, onCreated: (m) => created = m)),
    );

    await tester.enterText(find.byKey(const Key('keryx-new-group-name')), 'Site crew');
    // Real loopback HTTP via `DirectoryClient`/`FakeDirectoryServer` is
    // genuine `dart:io` socket I/O — the tap that kicks off the async
    // `createGroup` call must itself run inside `runAsync`'s real zone, or
    // the underlying socket event loop never actually drives (a fixed
    // `pumpAndSettle`/delayed-then-pump afterwards just times out at 10s,
    // the `DirectoryClient` request timeout).
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('keryx-new-group-create')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(created, isNotNull);
    expect(created.id, 'g1');
    expect(created.name, 'Site crew');
  });
}
