import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/groups/group_detail_controller.dart';
import 'package:keryx/features/groups/group_invite_link.dart';
import 'package:keryx/features/groups/group_invite_screen.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';

Widget _wrap(Widget child) => MaterialApp(theme: keryxUxThemeData(), home: child);

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late GroupsController groupsController;
  late GroupDetailController detailController;

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
      keyPair: keyPair);
    detailController = GroupDetailController(
      groupId: 'g1',
      groupsController: groupsController,
      directoryClient: directoryClient,
      keyPair: keyPair,
      myPk: 'me');
  });

  tearDown(() async {
    await detailController.dispose();
    await groupsController.dispose();
    directoryClient.close();
    await server.close();
  });

  testWidgets('mints an invite and renders a QR plus the encoded link honouring the preset', (tester) async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {'token': 'tok-1', 'group_id': 'g1', 'expires_at': null});
    final secret = List<int>.generate(32, (i) => i);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          GroupInviteScreen(
            controller: detailController,
            groupId: 'g1',
            secret: secret,
            initialPreset: EventLinkExpiryPreset.twentyFourHours)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('keryx-group-invite-qr')), findsOneWidget);
    final linkFinder = find.byKey(const Key('keryx-group-invite-link-text'));
    expect(linkFinder, findsOneWidget);
    final linkText = tester.widget<SelectableText>(linkFinder).data!;

    final decoded = decodeGroupInviteLink(linkText);
    expect(decoded, isA<GroupInviteDecoded>());
    final link = (decoded as GroupInviteDecoded).link;
    expect(link.groupId, 'g1');
    expect(link.token, 'tok-1');
    expect(link.secret, secret);
    expect(link.expiresAt, isNotNull);
    expect(link.isExpired(), isFalse);

    final inviteReq = server.requests.single;
    expect(inviteReq.path, '/v2/groups/g1/invites');
    expect(inviteReq.bodyJson!['expires_in'], const Duration(hours: 24).inSeconds);
  });

  testWidgets('offers every expiry preset in the picker', (tester) async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'token': 'tok', 'group_id': 'g1'});

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          GroupInviteScreen(
            controller: detailController,
            groupId: 'g1',
            secret: List<int>.generate(32, (i) => i))));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final dropdown = tester.widget<DropdownButton<EventLinkExpiryPreset>>(
      find.byKey(const Key('keryx-group-invite-expiry')));
    expect(dropdown.items!.map((i) => i.value), containsAll(EventLinkExpiryPreset.values));
  });

  testWidgets('shows a failure state when minting fails', (tester) async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 409, body: {'error': 'not_admin'});

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          GroupInviteScreen(
            controller: detailController,
            groupId: 'g1',
            secret: List<int>.generate(32, (i) => i))));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('keryx-group-invite-qr')), findsNothing);
  });
}
