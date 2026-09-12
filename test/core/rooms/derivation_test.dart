import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/keys.dart';
import 'package:keryx/core/rooms/rooms.dart';

void main() {
  test('keyed roomId is 16 uppercase RFC 4648 characters', () {
    final id = deriveKeyed(passphrase: 'secret');
    expect(id.length, roomIdLength);
    expect(isRoomId(id), isTrue);
    expect(id, id.toUpperCase());
    expect(roomIdPattern.hasMatch(id), isTrue);
  });

  test('empty passphrase is rejected', () {
    expect(() => deriveKeyed(passphrase: ''), throwsArgumentError);
  });

  test('keyed passphrase does not appear in the roomId', () {
    const passphrase = 'correct horse battery staple';
    final id = deriveKeyed(passphrase: passphrase);
    expect(id.contains(passphrase), isFalse);
    expect(id.toLowerCase().contains('horse'), isFalse);
    expect(isRoomId(id), isTrue);
  });

  test('same passphrase always yields the same keyed roomId', () {
    expect(
      deriveKeyed(passphrase: 'secret'),
      deriveKeyed(passphrase: 'secret'),
    );
  });

  test('leading/trailing passphrase spaces are entropy, not trimmed', () {
    expect(
      deriveKeyed(passphrase: 'secret'),
      isNot(deriveKeyed(passphrase: ' secret ')),
    );
  });

  test('scrypt parameters are the pinned dossier proposal', () {
    expect(KeyedScrypt.n, 32768);
    expect(KeyedScrypt.r, 8);
    expect(KeyedScrypt.p, 1);
    expect(KeyedScrypt.dkLen, 32);
    expect(KeyedScrypt.salt, keryxContext);
  });

  group('v2 group room (Technical §5.1)', () {
    test('stable for the same secret', () {
      final secret = List<int>.generate(32, (i) => i);
      expect(deriveGroupRoom(secret), deriveGroupRoom(secret));
      expect(isRoomId(deriveGroupRoom(secret)), isTrue);
    });

    test('changes after rotation (a different secret)', () {
      final a = List<int>.generate(32, (i) => i);
      final b = List<int>.generate(32, (i) => i + 1);
      expect(deriveGroupRoom(a), isNot(deriveGroupRoom(b)));
    });

    test('rejects an empty secret', () {
      expect(() => deriveGroupRoom(<int>[]), throwsArgumentError);
    });

    test('matches deriveKeyed(base64(secret)) directly', () {
      final secret = List<int>.generate(32, (i) => 255 - i);
      expect(
        deriveGroupRoom(secret),
        deriveKeyed(passphrase: base64Encode(secret)),
      );
    });
  });

  group('v2 1:1 room (Technical §5.4)', () {
    test('both sides derive the identical roomId', () async {
      final a = await IdentityKeyPair.generate();
      final b = await IdentityKeyPair.generate();
      final fromA = await deriveDirectRoom(
        myKeyPair: a,
        theirEdwardsPublicKey: b.publicKey,
      );
      final fromB = await deriveDirectRoom(
        myKeyPair: b,
        theirEdwardsPublicKey: a.publicKey,
      );
      expect(fromA, fromB);
      expect(isRoomId(fromA), isTrue);
    });

    test('a different pair yields a different roomId', () async {
      final a = await IdentityKeyPair.generate();
      final b = await IdentityKeyPair.generate();
      final c = await IdentityKeyPair.generate();
      final ab = await deriveDirectRoom(
        myKeyPair: a,
        theirEdwardsPublicKey: b.publicKey,
      );
      final ac = await deriveDirectRoom(
        myKeyPair: a,
        theirEdwardsPublicKey: c.publicKey,
      );
      expect(ab, isNot(ac));
    });

    test('deterministic across repeated calls with the same keys', () async {
      final a = await IdentityKeyPair.generate();
      final b = await IdentityKeyPair.generate();
      final first = await deriveDirectRoom(
        myKeyPair: a,
        theirEdwardsPublicKey: b.publicKey,
      );
      final second = await deriveDirectRoom(
        myKeyPair: a,
        theirEdwardsPublicKey: b.publicKey,
      );
      expect(first, second);
    });
  });

  test('library source never writes the passphrase (no I/O, no print)', () {
    final dir = Directory('lib/core/rooms');
    expect(dir.existsSync(), isTrue);
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      expect(src.contains('dart:io'), isFalse, reason: entity.path);
      expect(src.contains('print('), isFalse, reason: entity.path);
    }
  });
}
