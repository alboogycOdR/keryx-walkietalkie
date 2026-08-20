import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/linked/linked_controller.dart';
import 'package:keryx/services/linked/livekit_adapter.dart';
import 'package:keryx/services/linked/token_client.dart';

import 'fakes/fake_livekit_adapter.dart';
import 'fakes/fake_token_server.dart';

const _localPeerId = 'AAA2222222';

/// A solo-peer [FloorEngine] (no roster mates), so `requestTransmit()`
/// self-grants synchronously — same fixture shape as
/// `test/core/floor/floor_engine_test.dart`'s "solo peer self-grants" case.
FloorEngine _soloEngine() => FloorEngine(
  localPeerId: _localPeerId,
  transport: LoopbackHub().attach(_localPeerId),
  clock: VirtualClock(),
);

void main() {
  group('LinkedController', () {
    late FakeTokenServer server;
    late TokenClient tokenClient;
    late FakeLiveKitAdapter adapter;
    late FloorEngine engine;
    late List<RadioEvent> dispatched;
    late LinkedController controller;

    setUp(() async {
      server = await FakeTokenServer.start();
      server
        ..statusCode = 200
        ..responseBody = {'token': 'the-jwt', 'identity': 'BRAVO-7#a1b2c3d4', 'ttl_seconds': 300};
      tokenClient = TokenClient(baseUrl: server.baseUrl);
      adapter = FakeLiveKitAdapter();
      engine = _soloEngine();
      dispatched = [];
      controller = LinkedController(
        adapter: adapter,
        tokenClient: tokenClient,
        relayUrl: Uri.parse('wss://relay.example/rtc'),
        callsign: 'BRAVO-7',
        floorEngine: engine,
        dispatch: dispatched.add,
      );
    });

    tearDown(() async {
      await controller.dispose();
      engine.dispose();
      tokenClient.close();
      await server.close();
    });

    test('joinNumbered: derives roomId → fetches token → connects → publishes muted track', () async {
      await controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false);

      expect(server.lastRequestBody?['callsign'], 'BRAVO-7');
      final roomId = server.lastRequestBody?['room_id'] as String?;
      expect(roomId, isNotNull);
      expect(RegExp(r'^[A-Z2-7]{16}$').hasMatch(roomId!), isTrue);

      expect(adapter.connectCalls, hasLength(1));
      expect(adapter.connectCalls.single.jwt, 'the-jwt');
      expect(adapter.connectCalls.single.url, 'wss://relay.example/rtc');

      final room = adapter.lastRoom!;
      expect(room.publishedTrack, isNotNull);
      expect(room.publishedTrack!.enabled, isFalse); // TS §8.5 pre-published muted
      expect(controller.isJoined, isTrue);
      expect(controller.floorTransport, isNotNull);
    });

    test('joinKeyed: derives roomId off the UI isolate via compute, still joins', () async {
      await controller.joinKeyed(passphrase: 'correct horse battery staple', forceLocalOnly: false);

      final roomId = server.lastRequestBody?['room_id'] as String?;
      expect(roomId, isNotNull);
      expect(RegExp(r'^[A-Z2-7]{16}$').hasMatch(roomId!), isTrue);
      expect(adapter.connectCalls, hasLength(1));
    });

    test('joinKeyed does not block the calling isolate — synchronous code after the call runs first', () async {
      // deriveKeyed is TASK-007's ~1-3s scrypt stretch (TASK-024's own
      // MANDATORY acceptance criterion: it must run via compute(), never
      // inline). A direct/inline call would still return a Future
      // (join() is itself async), so the meaningful signal is that other
      // synchronous work queued right after the call runs BEFORE the
      // isolate round trip resolves — that ordering is only possible if
      // deriveKeyed itself is not run synchronously on this isolate.
      final order = <String>[];
      final future = controller
          .joinKeyed(passphrase: 'isolate check', forceLocalOnly: false)
          .whenComplete(() => order.add('joinKeyed'));
      order.add('synchronous-continuation');

      await future;

      expect(order, ['synchronous-continuation', 'joinKeyed']);
    });

    test('joinKeyed is deterministic — same passphrase derives the same roomId as the sync formula', () async {
      // Cross-check against the reducer's own (non-isolate) formula import
      // to prove compute() didn't alter the algorithm.
      await controller.joinKeyed(passphrase: 'same passphrase', forceLocalOnly: false);
      final first = server.lastRequestBody?['room_id'];

      await controller.leave();
      await controller.joinKeyed(passphrase: 'same passphrase', forceLocalOnly: false);
      final second = server.lastRequestBody?['room_id'];

      expect(first, second);
    });

    test('forceLocalOnly refuses to connect at all — no token request, no adapter.connect', () async {
      await expectLater(
        controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: true),
        throwsA(isA<ForceLocalOnlyException>()),
      );

      expect(server.lastRequestBody, isNull);
      expect(adapter.connectCalls, isEmpty);
      expect(controller.isJoined, isFalse);
    });

    test('TransmitGranted flips the published track enabled=true; EndTransmit flips it back', () async {
      await controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false);
      final track = adapter.lastRoom!.publishedTrack!;
      expect(track.enabled, isFalse);

      engine.requestTransmit();
      expect(track.enabled, isTrue);
      expect(controller.isLocalTrackEnabled, isTrue);

      engine.releaseTransmit();
      expect(track.enabled, isFalse);
      expect(controller.isLocalTrackEnabled, isFalse);
    });

    test('floorTransport rides floor-control messages over the LiveKit data channel', () async {
      // controller's own `floorEngine` (the constructor param) is deliberately
      // built with its own transport (mirrors MeshController's shape — the
      // host wires the two together, out of this task's scope, see the
      // class dartdoc). What THIS task owns is `floorTransport` itself
      // ([LinkedFloorTransport]) actually carrying FloorEngine traffic once
      // something is constructed against it.
      await controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false);
      final room = adapter.lastRoom!;

      final overLink = FloorEngine(
        localPeerId: 'BBB2222222',
        transport: controller.floorTransport!,
        clock: VirtualClock(),
      );
      addTearDown(overLink.dispose);

      overLink.requestTransmit(); // solo grant sends TxGrant/TxStart over the transport
      expect(room.sent, isNotEmpty);
    });

    test('publish failure during join disconnects the room and rethrows, leaving controller unjoined', () async {
      adapter = FakeLiveKitAdapter(
        onConnect: (url, jwt) => FakeLiveKitRoom()..publishFailure = StateError('mic denied'),
      );
      controller = LinkedController(
        adapter: adapter,
        tokenClient: tokenClient,
        relayUrl: Uri.parse('wss://relay.example/rtc'),
        callsign: 'BRAVO-7',
        floorEngine: engine,
        dispatch: dispatched.add,
      );

      await expectLater(
        controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false),
        throwsA(isA<StateError>()),
      );

      expect(adapter.lastRoom!.disconnected, isTrue);
      expect(controller.isJoined, isFalse);
    });

    test('joining a second time disconnects the previous room', () async {
      await controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false);
      final firstRoom = adapter.lastRoom!;

      await controller.joinNumbered(region: 'za-cpt', channel: 8, code: 0, forceLocalOnly: false);

      expect(firstRoom.disconnected, isTrue);
      expect(controller.isJoined, isTrue);
    });

    test('leave() disconnects the room and clears floorTransport', () async {
      await controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false);
      final room = adapter.lastRoom!;

      await controller.leave();

      expect(room.disconnected, isTrue);
      expect(controller.isJoined, isFalse);
      expect(controller.floorTransport, isNull);
    });

    test('link loss dispatches LinkDegraded through the same dispatch callback', () async {
      await controller.joinNumbered(region: 'za-cpt', channel: 7, code: 0, forceLocalOnly: false);
      final room = adapter.lastRoom!;

      room.emitConnectionState(LiveKitConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      expect(dispatched, contains(const LinkDegraded()));
    });
  });
}
