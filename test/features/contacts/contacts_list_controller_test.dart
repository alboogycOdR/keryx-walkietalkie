import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// HttpOverrides lives on dart:io; TestWidgetsFlutterBinding is not
// installed for these `test()` cases, but we still lift any mock in case
// this file is loaded next to widget tests in the same isolate.
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_list_controller.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late ContactsController contacts;
  late ContactsListController controller;
  var now = 1_000;

  setUp(() async {
    HttpOverrides.global = null; // in case a widget-test binding is present
    SharedPreferences.setMockInitialValues({});
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    contacts = ContactsController(
      directoryClient: directoryClient,
      repository: SharedPreferencesContactsRepository(await SharedPreferences.getInstance()),
      nowUnixSeconds: () => now,
    );
    controller = ContactsListController(
      contactsController: contacts,
      directoryClient: directoryClient,
      nowUnixSeconds: () => now,
    );
  });

  Future<void> cleanup() async {
    await controller.dispose();
    await contacts.dispose();
    directoryClient.close();
    await server.close();
  }

  test('accept moves an incoming request into the contacts list (V2-FR-011)', () async {
    server.responder = (req) {
      if (req.method == 'GET' && req.path == '/v2/identity/me') {
        return const DirectoryFakeResponse(
          statusCode: 200,
          body: {
            'pk': 'me',
            'callsign': 'ME',
            'status': 'available',
            'contacts': [],
            'pending_in': [
              {'from_pk': 'in1', 'callsign': 'Zed', 'created_at': 1, 'expires_at': 999999999999},
            ],
            'pending_out': [],
            'groups': [],
          },
        );
      }
      return const DirectoryFakeResponse(statusCode: 200, body: {});
    };

    await contacts.refreshFromServer();
    expect(controller.snapshot.requests.single.pk, 'in1');
    expect(controller.snapshot.contacts, isEmpty);

    await controller.accept('in1');

    expect(controller.snapshot.requests, isEmpty);
    expect(controller.snapshot.contacts.single.callsign, 'Zed');
    await cleanup();
  });

  test('a valid pasted ID sends a request; a tampered QR never hits the network', () async {
    await contacts.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});

    final tampered = await controller.sendRequestFromId('keryx://id?v=1&c=BEN&k=nope');
    expect(tampered, isA<ContactIdInvalid>());
    expect(server.requests, isEmpty);

    final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
    final parsed = await controller.sendRequestFromId(link.qrPayload);
    expect(parsed, isA<ContactIdParsed>());
    expect(server.requests.where((r) => r.path == '/v2/contacts/requests'), isNotEmpty);
    expect(controller.snapshot.contacts.single.isOutgoingPending, isTrue);
    await cleanup();
  });

  test('Alert is disabled for 10 minutes after a successful send (V2-FR-050)', () async {
    await contacts.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});

    expect(controller.isAlertDisabled('ada'), isFalse);
    final first = await controller.sendAlert('ada');
    expect(first, AlertSendResult.sent);
    expect(controller.isAlertDisabled('ada'), isTrue);

    now += 599;
    expect(controller.isAlertDisabled('ada'), isTrue);
    expect(await controller.sendAlert('ada'), AlertSendResult.cooldown);
    expect(server.requests.where((r) => r.path == '/v2/alerts').length, 1);

    now += 1;
    expect(controller.isAlertDisabled('ada'), isFalse);
    await cleanup();
  });

  test('server alert_rate_limited also disables the control', () async {
    await contacts.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 429,
      body: {'error': 'alert_rate_limited'},
    );

    final result = await controller.sendAlert('ada');
    expect(result, AlertSendResult.cooldown);
    expect(controller.isAlertDisabled('ada'), isTrue);
    await cleanup();
  });
}
