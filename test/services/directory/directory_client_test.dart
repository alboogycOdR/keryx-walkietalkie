import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/services/directory/directory.dart';

import 'fakes/fake_directory_server.dart';

void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DirectoryClient client;

  setUp(() async {
    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    client = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
  });
  tearDown(() async {
    client.close();
    await server.close();
  });

  test('every request carries valid signature headers with unpadded base64url key', () async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {'pk': 'abc', 'callsign': 'BRAVO-7'},
    );

    await client.registerIdentity('BRAVO-7');

    final recorded = server.requests.single;
    expect(recorded.headers['x-keryx-sig'], isNotEmpty);
    expect(recorded.headers['x-keryx-key'], isNotEmpty);
    expect(recorded.headers['x-keryx-key'], isNot(contains('=')));
    expect(recorded.headers['x-keryx-key'], matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(recorded.headers['x-keryx-ts'], isNotEmpty);

    // Same encoding directory_signing.dart itself computes.
    expect(recorded.headers['x-keryx-key'], unpaddedBase64Url(keyPair.publicKey));
  });

  test('registerIdentity parses pk/callsign', () async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {'pk': 'the-pk', 'callsign': 'BRAVO-7'},
    );
    final result = await client.registerIdentity('BRAVO-7');
    expect(result.pk, 'the-pk');
    expect(result.callsign, 'BRAVO-7');
    expect(server.requests.single.bodyJson, {'callsign': 'BRAVO-7'});
    expect(server.requests.single.method, 'POST');
    expect(server.requests.single.path, '/v2/identity');
  });

  test('getMe parses the full Me shape', () async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': 'me-pk',
        'callsign': 'BRAVO-7',
        'status': 'available',
        'contacts': [
          {'pk': 'c1', 'callsign': 'ALPHA-1', 'status': 'busy', 'last_seen_at': 100},
        ],
        'pending_in': [
          {'from_pk': 'p1', 'callsign': 'SIERRA-19', 'created_at': 10, 'expires_at': 20},
        ],
        'pending_out': [
          {'to_pk': 'p2', 'callsign': 'DELTA-4', 'created_at': 11, 'expires_at': 21},
        ],
        'groups': [
          {'id': 'g1', 'name': 'Team', 'role': 'admin', 'key_version': 1, 'secret_enc': 'ZGF0YQ=='},
        ],
      },
    );

    final me = await client.getMe();
    expect(me.pk, 'me-pk');
    expect(me.contacts.single.pk, 'c1');
    expect(me.pendingIn.single.fromPk, 'p1');
    expect(me.pendingOut.single.toPk, 'p2');
    expect(me.groups.single.id, 'g1');
    expect(server.requests.single.method, 'GET');
    expect(server.requests.single.path, '/v2/identity/me');
  });

  test('429 too_many_outstanding maps through DirectoryErrorCode.tooManyOutstanding', () async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 429,
      body: {'error': 'too_many_outstanding'},
    );

    await expectLater(
      client.sendContactRequest('some-pk'),
      throwsA(
        isA<DirectoryException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having((e) => e.code, 'code', DirectoryErrorCode.tooManyOutstanding),
      ),
    );
  });

  test('an unrecognised code still surfaces as DirectoryErrorCode.unknown, not a crash', () async {
    server.responder = (req) => const DirectoryFakeResponse(
      statusCode: 418,
      body: {'error': 'teapot_overheated'},
    );

    await expectLater(
      client.sendContactRequest('pk'),
      throwsA(isA<DirectoryException>().having((e) => e.code, 'code', DirectoryErrorCode.unknown)),
    );
  });

  test('unreachable host throws a transport DirectoryException, not a raw exception leak', () async {
    await server.close();
    await expectLater(
      client.getMe(),
      throwsA(isA<DirectoryException>().having((e) => e.isTransportFailure, 'isTransportFailure', isTrue)),
    );
  });

  test('createGroup posts name/my_secret_enc/room_id and parses the id back', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {'id': 'grp-1'});
    final created = await client.createGroup(
      name: 'Team',
      mySecretEnc: 'sealed==',
      roomId: 'ABCDEFGHIJKLMNOP',
    );
    expect(created.id, 'grp-1');
    expect(server.requests.single.bodyJson, {
      'name': 'Team',
      'my_secret_enc': 'sealed==',
      'room_id': 'ABCDEFGHIJKLMNOP',
    });
  });

  test('rotateGroup posts secrets_enc map and room_id', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    await client.rotateGroup(id: 'g1', secretsEnc: {'pkA': 'sealA', 'pkB': 'sealB'}, roomId: 'XYZ');
    expect(server.requests.single.path, '/v2/groups/g1/rotate');
    expect(server.requests.single.bodyJson, {
      'secrets_enc': {'pkA': 'sealA', 'pkB': 'sealB'},
      'room_id': 'XYZ',
    });
  });

  test('contact request lifecycle endpoints hit the expected paths', () async {
    server.responder = (req) => const DirectoryFakeResponse(statusCode: 200, body: {});
    await client.acceptContactRequest('fp');
    await client.declineContactRequest('fp');
    await client.blockContactRequest('fp');
    await client.removeContact('pk1');

    final paths = server.requests.map((r) => '${r.method} ${r.path}').toList();
    expect(paths, [
      'POST /v2/contacts/requests/fp:accept',
      'POST /v2/contacts/requests/fp:decline',
      'POST /v2/contacts/requests/fp:block',
      'DELETE /v2/contacts/pk1',
    ]);
  });
}
