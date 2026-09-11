import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  group('IdentityKeyPair', () {
    test('generate() yields a 32-byte seed and public key', () async {
      final keyPair = await IdentityKeyPair.generate();
      expect(keyPair.seed.length, identityKeyLength);
      expect(keyPair.publicKey.length, identityKeyLength);
    });

    test('fromSeed() is deterministic', () async {
      final seed = List<int>.generate(32, (i) => i);
      final a = await IdentityKeyPair.fromSeed(seed);
      final b = await IdentityKeyPair.fromSeed(seed);
      expect(a.publicKey, b.publicKey);
    });

    test('fromSeed() rejects a seed of the wrong length', () async {
      expect(
        () => IdentityKeyPair.fromSeed(List<int>.filled(31, 0)),
        throwsArgumentError,
      );
    });

    test('sign()/verifyEd25519() round-trip', () async {
      final keyPair = await IdentityKeyPair.generate();
      final message = 'hello keryx'.codeUnits;
      final signature = await keyPair.sign(message);
      expect(
        await verifyEd25519(message, signature, keyPair.publicKey),
        isTrue,
      );
    });

    test('verifyEd25519 rejects a tampered message', () async {
      final keyPair = await IdentityKeyPair.generate();
      final signature = await keyPair.sign('original'.codeUnits);
      expect(
        await verifyEd25519('tampered'.codeUnits, signature, keyPair.publicKey),
        isFalse,
      );
    });

    test('verifyEd25519 rejects the wrong public key', () async {
      final keyPair = await IdentityKeyPair.generate();
      final other = await IdentityKeyPair.generate();
      final signature = await keyPair.sign('message'.codeUnits);
      expect(
        await verifyEd25519('message'.codeUnits, signature, other.publicKey),
        isFalse,
      );
    });

    test('verifyEd25519 rejects a malformed signature without throwing', () async {
      final keyPair = await IdentityKeyPair.generate();
      expect(
        await verifyEd25519(
          'message'.codeUnits,
          List<int>.filled(10, 0),
          keyPair.publicKey,
        ),
        isFalse,
      );
    });
  });

  group('Ed25519 -> X25519 birational map', () {
    test(
      'private-scalar path and public-key conversion agree on the same '
      'Montgomery public key, for many random seeds',
      () async {
        for (var i = 0; i < 25; i++) {
          final keyPair = await IdentityKeyPair.generate();
          final x25519FromPrivate = await keyPair.toX25519KeyPair();
          final expectedPublic =
              (await x25519FromPrivate.extractPublicKey()).bytes;

          final convertedPublic = edwardsPublicKeyToX25519(
            keyPair.publicKey,
          );

          expect(
            convertedPublic,
            expectedPublic,
            reason: 'birational map mismatch on trial $i',
          );
        }
      },
    );

    test('rejects a public key of the wrong length', () {
      expect(
        () => edwardsPublicKeyToX25519(List<int>.filled(10, 0)),
        throwsFormatException,
      );
    });
  });
}
