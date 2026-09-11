import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/identity/sealed_box.dart';
import 'package:keryx/core/rooms/rooms.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';
import '../../services/directory/fakes/fake_presence_transport.dart';

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late SharedPreferencesGroupsRepository repository;
  late GroupsController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    repository = SharedPreferencesGroupsRepository(await SharedPreferences.getInstance());
    controller = GroupsController(directoryClient: directoryClient, repository: repository, keyPair: keyPair);
  });

  Future<void> cleanup() async {
    await controller.dispose();
    directoryClient.close();
    await server.close();
  }

  test('createGroup mints a secret, seals it to itself, and posts name/room_id', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});

    final membership = await controller.createGroup('Team');

    expect(membership.id, 'g1');
    expect(membership.role, 'admin');
    expect(membership.keyVersion, 1);
    expect(membership.secret, hasLength(32));
    expect(membership.roomId, deriveGroupRoom(membership.secret));

    final body = server.requests.single.bodyJson!;
    expect(body['name'], 'Team');
    expect(body['room_id'], membership.roomId);
    final sealed = base64Decode(body['my_secret_enc'] as String);
    final opened = await openSealed(sealed, keyPair);
    expect(opened, membership.secret);

    await cleanup();
  });

  test('joinGroup seals the invite secret to itself and posts token/my_secret_enc', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    final secret = List<int>.generate(32, (i) => i);

    final membership = await controller.joinGroup(
      groupId: 'g1',
      groupName: 'Team',
      token: 'invite-token',
      secret: secret,
    );

    expect(membership.secret, secret);
    expect(membership.role, 'member');
    final body = server.requests.single.bodyJson!;
    expect(body['token'], 'invite-token');
    final opened = await openSealed(base64Decode(body['my_secret_enc'] as String), keyPair);
    expect(opened, secret);

    await cleanup();
  });

  test('refreshFromServer opens a new group\'s sealed secret and adopts it', () async {
    final secret = List<int>.generate(32, (i) => 100 + i);
    final sealed = await sealToPublicKey(secret, keyPair.publicKey);
    server.responder = (req) => DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [], 'pending_out': [],
        'groups': [
          {
            'id': 'g1',
            'name': 'Team',
            'role': 'member',
            'key_version': 1,
            'secret_enc': base64Encode(sealed),
          },
        ],
      },
    );

    await controller.refreshFromServer();

    expect(controller.groupsSnapshot.single.id, 'g1');
    expect(controller.groupsSnapshot.single.secret, secret);
    expect(controller.groupsSnapshot.single.keyVersion, 1);

    await cleanup();
  });

  test('refreshFromServer drops a group no longer listed and emits GroupMembershipEnded', () async {
    final secret = List<int>.generate(32, (i) => i);
    final sealed = await sealToPublicKey(secret, keyPair.publicKey);
    server.responder = (req) => DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [], 'pending_out': [],
        'groups': [
          {'id': 'g1', 'name': 'Team', 'role': 'member', 'key_version': 1, 'secret_enc': base64Encode(sealed)},
        ],
      },
    );
    final events = <Object>[];
    controller.events.listen(events.add);
    await controller.refreshFromServer();
    expect(controller.groupsSnapshot, hasLength(1));

    // The next sync no longer lists g1 — I was removed.
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [], 'pending_out': [], 'groups': [],
      },
    );
    await controller.refreshFromServer();

    expect(controller.groupsSnapshot, isEmpty);
    expect(events.whereType<GroupMembershipEnded>().single.groupId, 'g1');

    await cleanup();
  });

  test('rotate posts secrets_enc/room_id, adopts the new secret, bumps key_version, emits GroupKeyChanged', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});
    await controller.createGroup('Team'); // key_version 1
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    final events = <Object>[];
    controller.events.listen(events.add);
    final newSecret = List<int>.generate(32, (i) => 200 + i);

    await controller.rotate(
      groupId: 'g1',
      newSecret: newSecret,
      secretsEncByPk: {'me-pk': 'sealed=='},
    );

    expect(controller.groupsSnapshot.single.keyVersion, 2);
    expect(controller.groupsSnapshot.single.secret, newSecret);
    expect(events.whereType<GroupKeyChanged>().single.keyVersion, 2);
    expect(server.requests.last.path, '/v2/groups/g1/rotate');

    await cleanup();
  });

  test('a presence rotation notice triggers a resync that adopts the new secret', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});
    await controller.createGroup('Team'); // key_version 1, secret S1
    final transport = FakePresenceTransport();
    final presence = PresenceClient(baseUrl: Uri.parse('wss://directory.example'), keyPair: keyPair, transport: transport);
    controller = GroupsController(
      directoryClient: directoryClient,
      repository: repository,
      keyPair: keyPair,
      presenceClient: presence,
    );
    await controller.loadFromDisk();
    await presence.start();

    final newSecret = List<int>.generate(32, (i) => 50 + i);
    final sealed = await sealToPublicKey(newSecret, keyPair.publicKey);
    server.responder = (req) => DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [], 'pending_out': [],
        'groups': [
          {'id': 'g1', 'name': 'Team', 'role': 'admin', 'key_version': 2, 'secret_enc': base64Encode(sealed)},
        ],
      },
    );

    transport.lastSocket!.deliver(jsonEncode({'type': 'rotation', 'group_id': 'g1', 'key_version': 2}));
    for (var i = 0; i < 50 && controller.groupsSnapshot.singleOrNull?.keyVersion != 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(controller.groupsSnapshot.single.secret, newSecret);
    expect(controller.groupsSnapshot.single.keyVersion, 2);

    await presence.dispose();
    await cleanup();
  });

  test('leave calls the API, drops the group locally, emits GroupMembershipEnded', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});
    await controller.createGroup('Team');
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    final events = <Object>[];
    controller.events.listen(events.add);

    await controller.leave('g1');

    expect(controller.groupsSnapshot, isEmpty);
    expect(events.whereType<GroupMembershipEnded>().single.groupId, 'g1');
    expect(server.requests.last.path, '/v2/groups/g1/members/me');

    await cleanup();
  });
}
