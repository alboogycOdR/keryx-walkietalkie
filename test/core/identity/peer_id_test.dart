import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

/// Frozen vectors. Changing these is a protocol break.
const vectorUuid = '00112233-4455-4677-8899-aabbccddeeff';
const vectorPeerId = 'wvuni74syc';
const vectorUuid2 = '550e8400-e29b-41d4-a716-446655440000';
const vectorPeerId2 = 'z3ucgb7gvv';

void main() {
  test('frozen vector: SHA-256(uuid bytes) → unpadded rfc4648[:10]', () {
    expect(derivePeerId(vectorUuid), vectorPeerId);
    expect(derivePeerId(vectorUuid2), vectorPeerId2);
  });

  test('peerId is 10 lowercase RFC 4648 characters', () {
    final id = derivePeerId(vectorUuid);
    expect(id.length, peerIdLength);
    expect(isPeerId(id), isTrue);
    expect(id, id.toLowerCase());
    expect(RegExp(r'^[a-z2-7]{10}$').hasMatch(id), isTrue);
  });

  test('same UUID always yields the same peerId (stability)', () {
    final a = derivePeerId(vectorUuid);
    final b = derivePeerId(vectorUuid);
    expect(a, b);
    expect(a, vectorPeerId);
  });

  test('UUID string case does not fork the peerId (bytes are hashed)', () {
    expect(derivePeerId(vectorUuid.toUpperCase()), vectorPeerId);
  });

  test('peerId is independent of any callsign', () {
    final fromUuid = derivePeerId(vectorUuid);
    final bravo = Callsign.parse('BRAVO-7');
    final sierra = Callsign.parse('SIERRA-19');
    expect(fromUuid, isNot(contains(bravo.value)));
    expect(fromUuid, isNot(contains(sierra.value)));
    expect(derivePeerId(vectorUuid), fromUuid);
  });

  test('malformed UUID is rejected', () {
    expect(() => derivePeerId('not-a-uuid'), throwsFormatException);
    expect(() => derivePeerId(''), throwsFormatException);
    expect(
      () => derivePeerId('00112233445546778899aabbccddeeff'),
      throwsFormatException,
    );
  });

  test('property: 500 random UUIDs produce unique valid peerIds', () {
    final rng = Random(42);
    final seen = <String>{};
    for (var i = 0; i < 500; i++) {
      final uuid = generateUuidV4(rng);
      expect(isCanonicalUuid(uuid), isTrue);
      final id = derivePeerId(uuid);
      expect(isPeerId(id), isTrue, reason: 'bad peerId $id from $uuid');
      expect(seen.add(id), isTrue, reason: 'collision $id at i=$i');
    }
    expect(seen.length, 500);
  });

  test('property: first-character distribution is not collapsed', () {
    final rng = Random(7);
    final firsts = <String>{};
    for (var i = 0; i < 200; i++) {
      firsts.add(derivePeerId(generateUuidV4(rng))[0]);
    }
    expect(
      firsts.length,
      greaterThanOrEqualTo(10),
      reason: 'expected a spread of RFC 4648 first characters, got $firsts',
    );
  });

  test('lexicographic min is over peerId, never the callsign', () {
    final peers = <ChannelPeer>[
      (peerId: vectorPeerId2, callsign: 'ALPHA-1'),
      (peerId: vectorPeerId, callsign: 'ZULU-99'),
    ];
    final elected = peers
        .map((p) => p.peerId)
        .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    expect(elected, vectorPeerId);
    expect(elected, isNot('ALPHA-1'));
    expect(displayNames(peers)[elected], 'ZULU-99');
  });
}
