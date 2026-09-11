import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  group('sealToPublicKey / openSealed', () {
    test('round-trips a group secret', () async {
      final recipient = await IdentityKeyPair.generate();
      final secret = List<int>.generate(32, (i) => i * 3 + 1);

      final sealed = await sealToPublicKey(secret, recipient.publicKey);
      final opened = await openSealed(sealed, recipient);

      expect(opened, secret);
    });

    test('opening with the wrong key fails', () async {
      final recipient = await IdentityKeyPair.generate();
      final impostor = await IdentityKeyPair.generate();
      final secret = 'top secret group key material'.codeUnits;

      final sealed = await sealToPublicKey(secret, recipient.publicKey);

      expect(
        () => openSealed(sealed, impostor),
        throwsA(isA<SealedBoxException>()),
      );
    });

    test('a tampered ciphertext fails to open', () async {
      final recipient = await IdentityKeyPair.generate();
      final secret = 'group secret'.codeUnits;
      final sealed = await sealToPublicKey(secret, recipient.publicKey);

      final tampered = List<int>.of(sealed);
      tampered[tampered.length - 1] ^= 0xff;

      expect(
        () => openSealed(tampered, recipient),
        throwsA(isA<SealedBoxException>()),
      );
    });

    test('a truncated box fails to open', () async {
      final recipient = await IdentityKeyPair.generate();
      expect(
        () => openSealed(List<int>.filled(10, 0), recipient),
        throwsA(isA<SealedBoxException>()),
      );
    });

    test('two seals of the same message to the same key differ (fresh nonce/ephemeral)', () async {
      final recipient = await IdentityKeyPair.generate();
      final secret = 'group secret'.codeUnits;
      final sealedA = await sealToPublicKey(secret, recipient.publicKey);
      final sealedB = await sealToPublicKey(secret, recipient.publicKey);
      expect(sealedA, isNot(sealedB));
    });
  });
}
