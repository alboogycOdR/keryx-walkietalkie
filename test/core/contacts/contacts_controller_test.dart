import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/directory/fakes/fake_directory_server.dart';
import '../../services/directory/fakes/fake_presence_transport.dart';

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient directoryClient;
  late SharedPreferencesContactsRepository repository;
  late ContactsController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    repository = SharedPreferencesContactsRepository(await SharedPreferences.getInstance());
    controller = ContactsController(directoryClient: directoryClient, repository: repository);
  });
  Future<void> cleanup() async {
    await controller.dispose();
    directoryClient.close();
    await server.close();
  }

  test('refreshFromServer reconciles contacts and pending in/out from getMe', () async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me',
        'callsign': 'ME',
        'status': 'available',
        'contacts': [
          {'pk': 'c1', 'callsign': 'ALPHA-1', 'status': 'busy', 'last_seen_at': 5},
        ],
        'pending_in': [
          {'from_pk': 'in1', 'callsign': 'SIERRA-19', 'created_at': 1, 'expires_at': 999999999999},
        ],
        'pending_out': [
          {'to_pk': 'out1', 'callsign': 'DELTA-4', 'created_at': 1, 'expires_at': 999999999999},
        ],
        'groups': [],
      },
    );

    await controller.refreshFromServer();

    expect(controller.contactsSnapshot.single.pk, 'c1');
    expect(controller.pendingSnapshot, hasLength(2));
    expect(
      controller.pendingSnapshot.where((p) => p.direction == ContactRequestDirection.incoming).single.pk,
      'in1',
    );
    expect(
      controller.pendingSnapshot.where((p) => p.direction == ContactRequestDirection.outgoing).single.pk,
      'out1',
    );
    await cleanup();
  });

  test('accept: removes the incoming pending row and adds a symmetric contact', () async {
    await controller.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    // Seed a pending-in row the way refreshFromServer would.
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [
          {'from_pk': 'p1', 'callsign': 'ALPHA-1', 'created_at': 1, 'expires_at': 999999999999},
        ],
        'pending_out': [], 'groups': [],
      },
    );
    await controller.refreshFromServer();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});

    await controller.accept('p1');

    expect(controller.pendingSnapshot, isEmpty);
    expect(controller.contactsSnapshot.single.pk, 'p1');
    expect(controller.contactsSnapshot.single.callsign, 'ALPHA-1');
    expect(server.requests.last.path, '/v2/contacts/requests/p1:accept');
    await cleanup();
  });

  test('decline: removes the pending row, no contact created', () async {
    await controller.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [
          {'from_pk': 'p1', 'callsign': 'ALPHA-1', 'created_at': 1, 'expires_at': 999999999999},
        ],
        'pending_out': [], 'groups': [],
      },
    );
    await controller.refreshFromServer();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});

    await controller.decline('p1');

    expect(controller.pendingSnapshot, isEmpty);
    expect(controller.contactsSnapshot, isEmpty);
    await cleanup();
  });

  test('block: removes the pending row and records the block locally', () async {
    await controller.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [
          {'from_pk': 'p1', 'callsign': 'ALPHA-1', 'created_at': 1, 'expires_at': 999999999999},
        ],
        'pending_out': [], 'groups': [],
      },
    );
    await controller.refreshFromServer();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});

    await controller.block('p1');

    expect(controller.pendingSnapshot, isEmpty);
    expect(controller.isBlocked('p1'), isTrue);
    await cleanup();
  });

  test('expiry: pruneExpired drops a pending row past its expiresAt', () async {
    var fakeNow = 1000;
    controller = ContactsController(
      directoryClient: directoryClient,
      repository: repository,
      nowUnixSeconds: () => fakeNow,
    );
    await controller.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available', 'contacts': [],
        'pending_in': [
          {'from_pk': 'p1', 'callsign': 'ALPHA-1', 'created_at': 900, 'expires_at': 1500},
        ],
        'pending_out': [], 'groups': [],
      },
    );
    await controller.refreshFromServer();
    expect(controller.pendingSnapshot, hasLength(1));

    fakeNow = 1600; // past expires_at
    controller.pruneExpired();

    expect(controller.pendingSnapshot, isEmpty);
    await cleanup();
  });

  test('sendRequest surfaces DirectoryException.tooManyOutstanding without corrupting local state', () async {
    await controller.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 429,
      body: {'error': 'too_many_outstanding'},
    );

    await expectLater(
      controller.sendRequest('someone', callsign: 'X'),
      throwsA(isA<DirectoryException>().having((e) => e.code, 'code', DirectoryErrorCode.tooManyOutstanding)),
    );
    expect(controller.pendingSnapshot, isEmpty); // not optimistically added on failure
    await cleanup();
  });

  test('sendRequest on success adds an outgoing pending row', () async {
    await controller.loadFromDisk();
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});

    await controller.sendRequest('someone', callsign: 'ROMEO-3');

    expect(controller.pendingSnapshot.single.pk, 'someone');
    expect(controller.pendingSnapshot.single.direction, ContactRequestDirection.outgoing);
    await cleanup();
  });

  test('presence updates merge status/lastSeenAt into an existing contact', () async {
    final transport = FakePresenceTransport();
    final presence = PresenceClient(
      baseUrl: Uri.parse('wss://directory.example'),
      keyPair: keyPair,
      transport: transport,
    );
    controller = ContactsController(
      directoryClient: directoryClient,
      repository: repository,
      presenceClient: presence,
    );
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me', 'callsign': 'ME', 'status': 'available',
        'contacts': [
          {'pk': 'c1', 'callsign': 'ALPHA-1', 'status': 'offline'},
        ],
        'pending_in': [], 'pending_out': [], 'groups': [],
      },
    );
    await controller.refreshFromServer();
    await presence.start();

    transport.lastSocket!.deliver('{"pk":"c1","status":"busy","since":42}');
    await Future<void>.delayed(Duration.zero);

    expect(controller.contactsSnapshot.single.status, 'busy');
    expect(controller.contactsSnapshot.single.lastSeenAt, 42);

    await presence.dispose();
    await cleanup();
  });
}
