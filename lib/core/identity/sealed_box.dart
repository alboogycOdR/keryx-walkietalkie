/// Sealed-box helpers for group secrets (Technical §5.1/§5.3): seal a
/// message to a recipient's Ed25519 identity public key so only that
/// recipient's private key can open it, with no shared state and no
/// server-visible plaintext.
///
/// Anonymous per-message ephemeral X25519 ECDH + HKDF-SHA256 + AES-256-GCM.
/// This is a KERYX-internal construction (not libsodium's `crypto_box_seal`
/// wire format): every sealer and opener is this Dart client, the server
/// never opens a sealed box (Technical §4.1's `secret_enc` comment), so
/// cross-language byte-compatibility is not a requirement here.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'keys.dart';

const _hkdfInfo = 'keryx-sealed-box-v1';
final X25519 _x25519 = X25519();
final AesGcm _aead = AesGcm.with256bits();

/// Thrown when [openSealed] cannot recover the plaintext: wrong key,
/// truncated input or a tampered ciphertext.
class SealedBoxException implements Exception {
  const SealedBoxException(this.message);
  final String message;

  @override
  String toString() => 'SealedBoxException: $message';
}

/// Seals [message] so only the holder of the private key behind
/// [recipientEdwardsPublicKey] (an Ed25519 identity public key) can
/// recover it. Returns `ephemeralPublicKey(32) || nonce(12) || ciphertext+tag`.
Future<Uint8List> sealToPublicKey(
  List<int> message,
  List<int> recipientEdwardsPublicKey,
) async {
  final recipientX25519 = edwardsPublicKeyToX25519(recipientEdwardsPublicKey);
  final ephemeral = await _x25519.newKeyPair();
  final ephemeralPublic = await ephemeral.extractPublicKey();

  final shared = await _x25519.sharedSecretKey(
    keyPair: ephemeral,
    remotePublicKey: SimplePublicKey(
      recipientX25519,
      type: KeyPairType.x25519,
    ),
  );
  final aeadKey = await _deriveAeadKey(shared);

  final box = await _aead.encrypt(message, secretKey: aeadKey);
  return Uint8List.fromList(<int>[
    ...ephemeralPublic.bytes,
    ...box.nonce,
    ...box.cipherText,
    ...box.mac.bytes,
  ]);
}

/// Opens a box produced by [sealToPublicKey] using the local identity's
/// [keyPair]. Throws [SealedBoxException] if [sealed] was addressed to a
/// different key or has been tampered with.
Future<Uint8List> openSealed(List<int> sealed, IdentityKeyPair keyPair) async {
  const ephemeralLen = identityKeyLength;
  const nonceLen = 12;
  const macLen = 16;
  if (sealed.length < ephemeralLen + nonceLen + macLen) {
    throw const SealedBoxException('sealed box is truncated');
  }
  final ephemeralPublic = sealed.sublist(0, ephemeralLen);
  final nonce = sealed.sublist(ephemeralLen, ephemeralLen + nonceLen);
  final cipherText = sealed.sublist(
    ephemeralLen + nonceLen,
    sealed.length - macLen,
  );
  final mac = sealed.sublist(sealed.length - macLen);

  final myX25519 = await keyPair.toX25519KeyPair();
  final SecretKey shared;
  try {
    shared = await _x25519.sharedSecretKey(
      keyPair: myX25519,
      remotePublicKey: SimplePublicKey(
        ephemeralPublic,
        type: KeyPairType.x25519,
      ),
    );
  } on Object catch (e) {
    throw SealedBoxException('could not derive shared secret: $e');
  }
  final aeadKey = await _deriveAeadKey(shared);

  try {
    final plain = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: aeadKey,
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw const SealedBoxException('wrong key or tampered ciphertext');
  }
}

Future<SecretKey> _deriveAeadKey(SecretKey shared) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  return hkdf.deriveKey(secretKey: shared, info: utf8.encode(_hkdfInfo));
}
