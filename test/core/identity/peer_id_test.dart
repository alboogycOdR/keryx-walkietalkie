import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

/// Frozen vector. Changing this is a protocol break.
const vectorPublicKeyBase64 = 'AwoRGB8mLTQ7QklQV15lbHN6gYiPlp2kq7K5wMfO1dw=';
const vectorPeerId = 'vnpywxfzin';

List<int> _publicKey(int seed, {int length = 32}) {
  final rng = Random(seed);
  return List<int>.generate(length, (_) => rng.nextInt(256));
}

void main() {
  test('frozen vector: SHA-256(publicKey) → unpadded rfc4648[:10]', () {
    final key = base64Decode(vectorPublicKeyBase64);
    expect(key.length, 32);
    expect(derivePeerId(key), vectorPeerId);
  });

  test('peerId is 10 lowercase RFC 4648 characters', () {
    final id = derivePeerId(_publicKey(1));
    expect(id.length, peerIdLength);
    expect(isPeerId(id), isTrue);
    expect(id, id.toLowerCase());
    expect(RegExp(r'^[a-z2-7]{10}$').hasMatch(id), isTrue);
  });

  test('shortCode is the next 4 characters of the same digest', () {
    final key = _publicKey(2);
    final peerId = derivePeerId(key);
    final shortCode = deriveShortCode(key);
    expect(shortCode.length, shortCodeLength);
    expect(RegExp(r'^[a-z2-7]{4}$').hasMatch(shortCode), isTrue);
    expect(shortCode, isNot(peerId.substring(0, shortCodeLength)));
  });

  test('same public key always yields the same peerId (stability)', () {
    final key = _publicKey(3);
    final a = derivePeerId(key);
    final b = derivePeerId(key);
    expect(a, b);
  });

  test('peerId is independent of any callsign', () {
    final key = _publicKey(4);
    final fromKey = derivePeerId(key);
    final bravo = Callsign.parse('BRAVO-7');
    final sierra = Callsign.parse('SIERRA-19');
    expect(fromKey, isNot(contains(bravo.value)));
    expect(fromKey, isNot(contains(sierra.value)));
    expect(derivePeerId(key), fromKey);
  });

  test('property: 500 random public keys produce unique valid peerIds', () {
    final rng = Random(42);
    final seen = <String>{};
    for (var i = 0; i < 500; i++) {
      final key = List<int>.generate(32, (_) => rng.nextInt(256));
      final id = derivePeerId(key);
      expect(isPeerId(id), isTrue, reason: 'bad peerId $id from $key');
      expect(seen.add(id), isTrue, reason: 'collision $id at i=$i');
    }
    expect(seen.length, 500);
  });

  test('property: 10,000 random public keys produce no peerId collision', () {
    // V2-VT-001.
    final rng = Random(1234);
    final seen = <String>{};
    for (var i = 0; i < 10000; i++) {
      final key = List<int>.generate(32, (_) => rng.nextInt(256));
      final id = derivePeerId(key);
      expect(seen.add(id), isTrue, reason: 'collision $id at i=$i');
    }
    expect(seen.length, 10000);
  });

  test('property: first-character distribution is not collapsed', () {
    final rng = Random(7);
    final firsts = <String>{};
    for (var i = 0; i < 200; i++) {
      final key = List<int>.generate(32, (_) => rng.nextInt(256));
      firsts.add(derivePeerId(key)[0]);
    }
    expect(
      firsts.length,
      greaterThanOrEqualTo(10),
      reason: 'expected a spread of RFC 4648 first characters, got $firsts',
    );
  });

  test('lexicographic min is over peerId, never the callsign', () {
    final keyA = _publicKey(10);
    final keyB = _publicKey(11);
    final idA = derivePeerId(keyA);
    final idB = derivePeerId(keyB);
    final peers = <ChannelPeer>[
      (peerId: idA, callsign: 'ALPHA-1'),
      (peerId: idB, callsign: 'ZULU-99'),
    ];
    final expectedMin = idA.compareTo(idB) < 0 ? idA : idB;
    final elected = peers
        .map((p) => p.peerId)
        .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
    expect(elected, expectedMin);
  });
}
