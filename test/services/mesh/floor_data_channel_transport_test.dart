import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/services/mesh/floor_data_channel_transport.dart';

import 'fakes/fake_rtc_adapter.dart';

void main() {
  group('MeshFloorTransport', () {
    late MeshFloorTransport transport;

    setUp(() => transport = MeshFloorTransport());
    tearDown(() => transport.dispose());

    test('decodes an inbound wire message into FloorMessage', () async {
      final channel = FakeDataChannel(label: 'floor');
      transport.attach('bravo', channel);

      final received = <FloorMessage>[];
      final sub = transport.incoming.listen(received.add);

      channel.deliver(
        FloorCodec.encode(const TxStart(peer: 'bravo')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(received, [const TxStart(peer: 'bravo')]);
      await sub.cancel();
    });

    test('ignores malformed inbound text rather than throwing', () async {
      final channel = FakeDataChannel(label: 'floor');
      transport.attach('bravo', channel);

      final received = <FloorMessage>[];
      final sub = transport.incoming.listen(received.add);

      expect(() => channel.deliver('not json'), returnsNormally);
      expect(() => channel.deliver('{"v":1,"t":"NOPE"}'), returnsNormally);
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });

    test('send() fans out to every attached open channel', () {
      final a = FakeDataChannel(label: 'floor');
      final b = FakeDataChannel(label: 'floor');
      transport.attach('alpha', a);
      transport.attach('bravo', b);

      transport.send(const TxEnd(peer: 'local'));

      expect(a.sent, [FloorCodec.encode(const TxEnd(peer: 'local'))]);
      expect(b.sent, [FloorCodec.encode(const TxEnd(peer: 'local'))]);
    });

    test('send() skips channels that are not open', () {
      final open = FakeDataChannel(label: 'floor');
      final closed = FakeDataChannel(label: 'floor', open: false);
      transport.attach('alpha', open);
      transport.attach('bravo', closed);

      transport.send(const TxStart(peer: 'local'));

      expect(open.sent, hasLength(1));
      expect(closed.sent, isEmpty);
    });

    test('detach() stops fan-out to that peer', () {
      final a = FakeDataChannel(label: 'floor');
      transport.attach('alpha', a);
      transport.detach('alpha');

      transport.send(const TxStart(peer: 'local'));

      expect(a.sent, isEmpty);
    });
  });
}
