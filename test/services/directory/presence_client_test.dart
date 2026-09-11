import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/services/directory/presence_client.dart';

import 'fakes/fake_presence_transport.dart';

void main() {
  late FakePresenceTransport transport;
  late IdentityKeyPair keyPair;
  late PresenceClient client;

  setUp(() async {
    transport = FakePresenceTransport();
    keyPair = await IdentityKeyPair.generate();
  });

  PresenceClient makeClient({
    Duration heartbeatInterval = const Duration(seconds: 60),
    Duration initialBackoff = const Duration(milliseconds: 1),
    Duration maxBackoff = const Duration(milliseconds: 4),
    int maxAttempts = 5,
  }) {
    client = PresenceClient(
      baseUrl: Uri.parse('wss://directory.example'),
      keyPair: keyPair,
      transport: transport,
      heartbeatInterval: heartbeatInterval,
      initialBackoff: initialBackoff,
      maxBackoff: maxBackoff,
      maxAttempts: maxAttempts,
    );
    return client;
  }

  tearDown(() async {
    await client.dispose();
  });

  test('connects to /v2/presence with signed headers, empty body', () async {
    makeClient();
    await client.start();

    final call = transport.connectCalls.single;
    expect(call.url.path, '/v2/presence');
    expect(call.headers['X-Keryx-Sig'], isNotEmpty);
    expect(call.headers['X-Keryx-Key'], isNotEmpty);
    expect(call.headers['X-Keryx-Ts'], isNotEmpty);
  });

  test('surfaces a PresenceUpdate from a plain {pk,status,since} frame', () async {
    makeClient();
    await client.start();
    final updates = <PresenceUpdate>[];
    client.updates.listen(updates.add);

    transport.lastSocket!.deliver(jsonEncode({'pk': 'abc', 'status': 'available', 'since': 100}));
    await Future<void>.delayed(Duration.zero);

    expect(updates.single.pk, 'abc');
    expect(updates.single.status, 'available');
    expect(updates.single.since, 100);
  });

  test('surfaces a rotation notice and an alert distinctly from status updates', () async {
    makeClient();
    await client.start();
    final rotations = <GroupRotationNotice>[];
    final alerts = <AlertNotice>[];
    client.rotationNotices.listen(rotations.add);
    client.alerts.listen(alerts.add);

    transport.lastSocket!.deliver(jsonEncode({'type': 'rotation', 'group_id': 'g1', 'key_version': 2}));
    transport.lastSocket!.deliver(jsonEncode({'type': 'alert', 'from_pk': 'x', 'since': 5}));
    await Future<void>.delayed(Duration.zero);

    expect(rotations.single.groupId, 'g1');
    expect(rotations.single.keyVersion, 2);
    expect(alerts.single.fromPk, 'x');
  });

  test('setStatus sends {"status":...} on the live socket', () async {
    makeClient();
    await client.start();

    client.setStatus(LocalPresenceStatus.busy);

    expect(transport.lastSocket!.sent, contains(jsonEncode({'status': 'busy'})));
  });

  test('a status set before connect is queued and sent once connected', () async {
    makeClient();
    client.setStatus(LocalPresenceStatus.dnd); // before start()
    await client.start();

    expect(transport.lastSocket!.sent, contains(jsonEncode({'status': 'dnd'})));
  });

  test('sends a heartbeat every heartbeatInterval', () async {
    makeClient(heartbeatInterval: const Duration(milliseconds: 20));
    await client.start();

    await Future<void>.delayed(const Duration(milliseconds: 55));

    final heartbeats = transport.lastSocket!.sent.where((s) => s == jsonEncode({'type': 'heartbeat'}));
    expect(heartbeats.length, greaterThanOrEqualTo(2));
  });

  test('reconnects with backoff after the server closes the socket', () async {
    makeClient(initialBackoff: const Duration(milliseconds: 5), maxBackoff: const Duration(milliseconds: 10));
    await client.start();
    final connectedStates = <bool>[];
    client.connectionState.listen(connectedStates.add);

    transport.lastSocket!.simulateServerClose();
    // Wait through backoff + reconnect.
    for (var i = 0; i < 50 && transport.connectCalls.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(transport.connectCalls.length, greaterThanOrEqualTo(2));
    expect(connectedStates, contains(false));
    expect(client.isConnected, isTrue);
  });

  test('gives up after maxAttempts consecutive failures', () async {
    transport = FakePresenceTransport(
      onConnect: (url, headers) => throw StateError('unreachable'),
    );
    makeClient(
      initialBackoff: const Duration(milliseconds: 2),
      maxBackoff: const Duration(milliseconds: 4),
      maxAttempts: 3,
    );

    await client.start(); // first attempt fails synchronously inside _connect's try/catch

    for (var i = 0; i < 100 && !client.gaveUp; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    expect(client.gaveUp, isTrue);
    expect(client.isConnected, isFalse);
  });
}
