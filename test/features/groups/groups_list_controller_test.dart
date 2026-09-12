import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/features/groups/group_view_models.dart';
import 'package:keryx/features/groups/groups_list_controller.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late GroupsController groupsController;
  late GroupsListController listController;

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
    listController = GroupsListController(groupsController: groupsController, directoryClient: directoryClient);
  });

  Future<void> cleanup() async {
    await listController.dispose();
    await groupsController.dispose();
    directoryClient.close();
    await server.close();
  }

  test('emits an empty row list before any group exists', () async {
    final rows = <List<GroupListRow>>[];
    final sub = listController.rows.listen(rows.add);
    await groupsController.loadFromDisk();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(rows.last, isEmpty);

    await sub.cancel();
    await cleanup();
  });

  test('a created group appears with online/member counts from the detail fetch', () async {
    server.responder = (req) {
      if (req.method == 'POST' && req.path == '/v2/groups') {
        return const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});
      }
      if (req.method == 'GET' && req.path == '/v2/groups/g1') {
        return const DirectoryFakeResponse(
          statusCode: 200,
          body: {
            'id': 'g1', 'name': 'Team',
            'members': [
              {'pk': 'me', 'callsign': 'Me', 'role': 'admin', 'status': 'available'},
              {'pk': 'b', 'callsign': 'Bob', 'role': 'member', 'status': 'offline'},
            ],
          },
        );
      }
      return const DirectoryFakeResponse(statusCode: 200, body: {});
    };

    final rows = <List<GroupListRow>>[];
    final sub = listController.rows.listen(rows.add);
    await groupsController.createGroup('Team');
    for (var i = 0; i < 50 && (rows.isEmpty || rows.last.isEmpty || rows.last.single.totalCount == 0); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final row = rows.last.single;
    expect(row.name, 'Team');
    expect(row.totalCount, 2);
    expect(row.onlineCount, 1);
    expect(row.isAdmin, isTrue);

    await sub.cancel();
    await cleanup();
  });

  test('a per-group detail-fetch failure does not blank the whole list', () async {
    server.responder = (req) {
      if (req.method == 'POST' && req.path == '/v2/groups') {
        return const DirectoryFakeResponse(statusCode: 200, body: {'id': 'g1'});
      }
      if (req.method == 'GET' && req.path == '/v2/groups/g1') {
        return const DirectoryFakeResponse(statusCode: 500, body: {});
      }
      return const DirectoryFakeResponse(statusCode: 200, body: {});
    };

    final rows = <List<GroupListRow>>[];
    final sub = listController.rows.listen(rows.add);
    await groupsController.createGroup('Team');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(rows.last, hasLength(1));
    expect(rows.last.single.totalCount, 0);

    await sub.cancel();
    await cleanup();
  });
}
