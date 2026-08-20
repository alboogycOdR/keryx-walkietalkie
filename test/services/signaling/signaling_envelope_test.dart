import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/signaling/signaling.dart';

void main() {
  const offer = SignalingEnvelope(
    type: SignalingType.offer,
    from: 'aaaaaaaaaa',
    to: 'bbbbbbbbbb',
    payload: {'sdp': 'v=0'},
  );

  test('round-trips offer/answer/ice/hello', () {
    expect(SignalingEnvelope.decode(offer.encode()), offer);

    const hello = SignalingEnvelope(
      type: SignalingType.hello,
      from: 'aaaaaaaaaa',
      to: 'bbbbbbbbbb',
      payload: {'cs': 'BRAVO-7', 'ch': 'aabbccdd'},
    );
    expect(SignalingEnvelope.decode(hello.encode()), hello);

    const ice = SignalingEnvelope(
      type: SignalingType.iceCandidate,
      from: 'aaaaaaaaaa',
      to: 'bbbbbbbbbb',
      payload: {
        'candidate': 'candidate:0 1 UDP 2122260223 10.0.0.8 9 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      },
    );
    expect(SignalingEnvelope.decode(ice.encode()), ice);
  });

  test('unknown version/type and malformed JSON are ignored', () {
    expect(SignalingEnvelope.decode('not-json'), isNull);
    expect(
      SignalingEnvelope.decode(
        jsonEncode({
          'v': 99,
          'type': 'offer',
          'from': 'aaaaaaaaaa',
          'to': 'bbbbbbbbbb',
          'payload': {'sdp': 'v=0'},
        }),
      ),
      isNull,
    );
    expect(
      SignalingEnvelope.decode(
        jsonEncode({
          'v': 1,
          'type': 'nope',
          'from': 'aaaaaaaaaa',
          'to': 'bbbbbbbbbb',
          'payload': {},
        }),
      ),
      isNull,
    );
    expect(
      SignalingEnvelope.decode(
        jsonEncode({
          'v': 1,
          't': 'PRESENCE',
          'peer': 'aaaaaaaaaa',
          'cs': 'BRAVO-7',
          'seq': 1,
        }),
      ),
      isNull,
    );
  });

  test('lanFiltered drops non-LAN ICE and sanitizes SDP', () {
    const relay = SignalingEnvelope(
      type: SignalingType.iceCandidate,
      from: 'aaaaaaaaaa',
      to: 'bbbbbbbbbb',
      payload: {'candidate': 'candidate:3 1 UDP 41819903 1.1.1.1 9 typ relay'},
    );
    expect(relay.lanFiltered(), isNull);

    const mixed = SignalingEnvelope(
      type: SignalingType.offer,
      from: 'aaaaaaaaaa',
      to: 'bbbbbbbbbb',
      payload: {
        'sdp':
            'v=0\na=candidate:0 1 UDP 2122260223 10.0.0.8 9 typ host\n'
            'a=candidate:2 1 UDP 1 203.0.113.9 9 typ srflx\n',
      },
    );
    final cleaned = mixed.lanFiltered();
    expect(cleaned, isNotNull);
    expect(cleaned!.sdp, contains('typ host'));
    expect(cleaned.sdp, isNot(contains('typ srflx')));
  });

  test('wire key is type, not t — discriminator vs FloorCodec', () {
    final decoded = jsonDecode(offer.encode()) as Map<String, dynamic>;
    expect(decoded.containsKey('type'), isTrue);
    expect(decoded.containsKey('t'), isFalse);
    expect(decoded['v'], 1);
    expect(decoded['from'], 'aaaaaaaaaa');
    expect(decoded['to'], 'bbbbbbbbbb');
  });
}
