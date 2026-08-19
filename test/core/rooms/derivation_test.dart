import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/rooms/rooms.dart';

void main() {
  test('roomId is 16 uppercase RFC 4648 characters', () {
    final id = deriveNumbered(region: 'global', channel: 7, code: 21);
    expect(id.length, roomIdLength);
    expect(isRoomId(id), isTrue);
    expect(id, id.toUpperCase());
    expect(roomIdPattern.hasMatch(id), isTrue);
  });

  test('numbered HMAC matches an independent crypto oracle', () {
    final message = utf8.encode('global|07|21');
    final digest = Hmac(sha256, utf8.encode(keryxContext)).convert(message);
    final expected = encodeRfc4648Base32(digest.bytes).substring(0, 16);
    expect(deriveNumbered(region: 'global', channel: 7, code: 21), expected);
    expect(expected, 'M5MFIUI6TXTBOHBD');
  });

  test('region salt partitions the numbered namespace (FR-008)', () {
    final cape = deriveNumbered(region: 'za-cpt', channel: 7, code: 21);
    final sao = deriveNumbered(region: 'sao-paulo', channel: 7, code: 21);
    final global = deriveNumbered(region: 'global', channel: 7, code: 21);
    expect(cape, isNot(sao));
    expect(cape, isNot(global));
    expect(sao, isNot(global));
    expect({cape, sao, global}.length, 3);
  });

  test('privacy code participates in numbered derivation (FR-002)', () {
    final open = deriveNumbered(region: 'global', channel: 7, code: 0);
    final coded = deriveNumbered(region: 'global', channel: 7, code: 21);
    expect(open, isNot(coded));
    expect(open, '5KE6UYJZEWK5KGWQ');
    expect(coded, 'M5MFIUI6TXTBOHBD');
  });

  test('channel number participates in numbered derivation', () {
    final a = deriveNumbered(region: 'global', channel: 7, code: 21);
    final b = deriveNumbered(region: 'global', channel: 8, code: 21);
    expect(a, isNot(b));
  });

  test('region trim does not fork; surrounding space is not salt', () {
    expect(
      deriveNumbered(region: '  global  ', channel: 7, code: 21),
      deriveNumbered(region: 'global', channel: 7, code: 21),
    );
  });

  test('out-of-domain channel and code are rejected', () {
    expect(
      () => deriveNumbered(region: 'global', channel: 0, code: 0),
      throwsArgumentError,
    );
    expect(
      () => deriveNumbered(region: 'global', channel: 100, code: 0),
      throwsArgumentError,
    );
    expect(
      () => deriveNumbered(region: 'global', channel: 1, code: -1),
      throwsArgumentError,
    );
    expect(
      () => deriveNumbered(region: 'global', channel: 1, code: 39),
      throwsArgumentError,
    );
  });

  test('empty or pipe-bearing region is rejected', () {
    expect(
      () => deriveNumbered(region: '', channel: 1, code: 0),
      throwsArgumentError,
    );
    expect(
      () => deriveNumbered(region: '   ', channel: 1, code: 0),
      throwsArgumentError,
    );
    expect(
      () => deriveNumbered(region: 'za|cpt', channel: 1, code: 0),
      throwsArgumentError,
    );
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

  test('keyed and numbered formulas do not collide on "PRV"', () {
    final numbered = deriveNumbered(region: 'PRV', channel: 1, code: 0);
    final keyed = deriveKeyed(passphrase: 'PRV');
    expect(numbered, isNot(keyed));
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
