import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/services/linked/linked_floor_transport.dart';

import 'fakes/fake_livekit_adapter.dart';

void main() {
  group('LinkedFloorTransport', () {
    late FakeLiveKitRoom room;
    late LinkedFloorTransport transport;

    setUp(() {
      room = FakeLiveKitRoom();
      transport = LinkedFloorTransport(room);
    });
    tearDown(() => transport.dispose());

    test('decodes an inbound data message into FloorMessage', () async {
      final received = <FloorMessage>[];
      final sub = transport.incoming.listen(received.add);

      room.deliverData(utf8.encode(FloorCodec.encode(const TxStart(peer: 'bravo'))));
      await Future<void>.delayed(Duration.zero);

      expect(received, [const TxStart(peer: 'bravo')]);
      await sub.cancel();
    });

    test('ignores malformed inbound data rather than throwing', () async {
      final received = <FloorMessage>[];
      final sub = transport.incoming.listen(received.add);

      expect(() => room.deliverData(utf8.encode('not json')), returnsNormally);
      expect(() => room.deliverData(utf8.encode('{"v":1,"t":"NOPE"}')), returnsNormally);
      expect(() => room.deliverData([0xFF, 0xFE, 0xFD]), returnsNormally); // non-UTF8
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });

    test('send() publishes the encoded wire message via the room', () {
      transport.send(const TxEnd(peer: 'local'));

      expect(room.sent, hasLength(1));
      expect(utf8.decode(room.sent.single), FloorCodec.encode(const TxEnd(peer: 'local')));
    });

    test('send() after dispose is a no-op, never throws', () async {
      await transport.dispose();
      expect(() => transport.send(const TxStart(peer: 'local')), returnsNormally);
      expect(room.sent, isEmpty);
    });

    test('dispose() stops delivering further inbound messages', () async {
      final received = <FloorMessage>[];
      final sub = transport.incoming.listen(received.add);
      await transport.dispose();

      // Room-level delivery after transport dispose must not throw or leak
      // into a closed stream controller.
      expect(() => room.deliverData(utf8.encode(FloorCodec.encode(const TxStart(peer: 'x')))), returnsNormally);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });
  });
}
