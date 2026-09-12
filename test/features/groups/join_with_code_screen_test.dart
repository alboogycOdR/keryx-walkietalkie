import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/groups/group_invite_link.dart';
import 'package:keryx/features/groups/groups_copy.dart';
import 'package:keryx/features/groups/join_with_code_screen.dart';
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

  testWidgets('an invalid pasted link shows the invalid-link message', (tester) async {
    await tester.pumpWidget(
      _wrap(JoinWithCodeScreen(groupsController: groupsController, onJoined: (_) {})),
    );

    await tester.enterText(find.byKey(const Key('keryx-join-code-paste')), 'not a link');
    await tester.tap(find.byKey(const Key('keryx-join-code-submit')));
    await tester.pump();

    expect(find.text(GroupsCopy.invalidInviteLink), findsOneWidget);
  });

  testWidgets('an expired invite link is refused locally, no network call made', (tester) async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    final expiredLink = GroupInviteLink(
      groupId: 'g1',
      token: 'tok',
      secret: List<int>.generate(32, (i) => i),
      expiresAt: DateTime.utc(2020),
    );
    final uri = encodeGroupInviteLink(expiredLink);

    await tester.pumpWidget(
      _wrap(JoinWithCodeScreen(groupsController: groupsController, onJoined: (_) {})),
    );

    await tester.enterText(find.byKey(const Key('keryx-join-code-paste')), uri.toString());
    await tester.tap(find.byKey(const Key('keryx-join-code-submit')));
    await tester.pump();

    expect(find.text(GroupsCopy.expiredInviteLink), findsOneWidget);
    expect(server.requests, isEmpty);
  });

  testWidgets('a valid, unexpired invite link joins and calls onJoined', (tester) async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    final link = GroupInviteLink(
      groupId: 'g1',
      token: 'tok',
      secret: List<int>.generate(32, (i) => i),
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    final uri = encodeGroupInviteLink(link);

    dynamic joined;
    await tester.pumpWidget(
      _wrap(JoinWithCodeScreen(groupsController: groupsController, onJoined: (m) => joined = m)),
    );

    await tester.enterText(find.byKey(const Key('keryx-join-code-paste')), uri.toString());
    // Real loopback HTTP — the tap itself must run inside `runAsync`'s
    // real zone (see `new_group_screen_test.dart`'s identical fix note).
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('keryx-join-code-submit')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(joined, isNotNull);
    expect(joined.id, 'g1');
    expect(server.requests, isNotEmpty);
  });
}
