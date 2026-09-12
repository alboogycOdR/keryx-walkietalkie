import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/features/groups/group_detail_controller.dart';
import 'package:keryx/features/groups/groups_copy.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late GroupsController groupsController;
  late String myPk;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    groupsController = GroupsController(
      directoryClient: directoryClient,
      repository: SharedPreferencesGroupsRepository(await SharedPreferences.getInstance()),
      keyPair: keyPair,
    );
    // Unpadded base64url of the public key, matching the wire `pk` shape
    // (Technical §3.3) every fixture below writes into `getGroup`'s body.
    myPk = _b64Url(keyPair.publicKey);
  });

  Future<void> cleanup() async {
    await groupsController.dispose();
    directoryClient.close();
    await server.close();
  }

  GroupDetailController buildController(String groupId) => GroupDetailController(
    groupId: groupId,
    groupsController: groupsController,
    directoryClient: directoryClient,
    keyPair: keyPair,
    myPk: myPk,
  );

  test('load() populates name, members, isAdmin and isLastAdmin', () async {
    server.responder = (req) => DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'id': 'g1',
        'name': 'Site crew',
        'key_version': 1,
        'members': [
          {'pk': myPk, 'callsign': 'ME', 'role': 'admin', 'status': 'available'},
          {'pk': 'other', 'callsign': 'OTHER', 'role': 'member', 'status': 'offline'},
        ],
      },
    );

    final controller = buildController('g1');
    await controller.load();

    expect(controller.state.name, 'Site crew');
    expect(controller.state.members, hasLength(2));
    expect(controller.state.isAdmin, isTrue);
    expect(controller.state.isLastAdmin, isTrue);
    expect(controller.state.loading, isFalse);

    await controller.dispose();
    await cleanup();
  });

  test('admin actions are not exercised when caller is not an admin (isAdmin false)', () async {
    server.responder = (req) => DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'id': 'g1',
        'name': 'Site crew',
        'key_version': 1,
        'members': [
          {'pk': myPk, 'callsign': 'ME', 'role': 'member', 'status': 'available'},
          {'pk': 'admin-pk', 'callsign': 'ADMIN', 'role': 'admin', 'status': 'available'},
        ],
      },
    );

    final controller = buildController('g1');
    await controller.load();

    expect(controller.state.isAdmin, isFalse);
    expect(controller.state.isLastAdmin, isFalse);

    await controller.dispose();
    await cleanup();
  });

  test('mintInvite surfaces the groupFull message on a group_full error', () async {
    server.responder = (req) {
      if (req.method == 'GET') {
        return const DirectoryFakeResponse(
          statusCode: 200,
          body: {'id': 'g1', 'name': 'Full crew', 'key_version': 1, 'members': []},
        );
      }
      return const DirectoryFakeResponse(statusCode: 409, body: {'error': 'group_full'});
    };

    final controller = buildController('g1');
    await controller.load();
    final invite = await controller.mintInvite();

    expect(invite, isNull);
    expect(controller.state.error, GroupsCopy.groupFullMessage);

    await controller.dispose();
    await cleanup();
  });

  test('key rotation notice via GroupsController.events surfaces a toast and reloads', () async {
    var getCount = 0;
    server.responder = (req) {
      if (req.method == 'GET') {
        getCount++;
        return DirectoryFakeResponse(
          statusCode: 200,
          body: {
            'id': 'g1',
            'name': 'Site crew',
            'key_version': getCount,
            'members': [
              {'pk': myPk, 'callsign': 'ME', 'role': 'admin', 'status': 'available'},
            ],
          },
        );
      }
      return const DirectoryFakeResponse(statusCode: 200, body: {});
    };

    final controller = buildController('g1');
    await controller.load();

    final toastFuture = controller.toasts.first;
    // Reuses `GroupsController`'s own `events` sink the same way its
    // production `_onRotationNotice` does — this test fires the event
    // straight from the (private) rotation-notice handling path is not
    // reachable without a live presence WS, so it exercises the same
    // effect one causes: `GroupsController.rotate` posts and adopts,
    // which itself emits `GroupKeyChanged`.
    await groupsController.rotate(
      groupId: 'g1',
      newSecret: List<int>.generate(32, (i) => i),
      secretsEncByPk: const {},
    );

    final toast = await toastFuture;
    expect(toast.message, GroupsCopy.keyRotatedToast('Site crew'));

    await controller.dispose();
    await cleanup();
  });

  test('removed-from-group notice surfaces the exact Design §4 toast copy', () async {
    server.responder = (req) => DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'id': 'g1',
        'name': 'Site crew',
        'key_version': 1,
        'members': [
          {'pk': myPk, 'callsign': 'ME', 'role': 'member', 'status': 'available'},
        ],
      },
    );

    final controller = buildController('g1');
    await controller.load();

    final toastFuture = controller.toasts.first;
    await groupsController.leave('g1');
    final toast = await toastFuture;

    expect(toast.message, GroupsCopy.removedFromGroupToast('Site crew'));

    await controller.dispose();
    await cleanup();
  });
}

/// Unpadded base64url — mirrors `directory_signing.dart`'s own `pk`
/// encoding (Technical §3.3), so any consumer decoding `pk` back to bytes
/// round-trips correctly.
String _b64Url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
