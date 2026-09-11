/// Ed25519 identity keys and their birational Curve25519 (X25519)
/// counterparts, used for request signing and sealed-box encryption.
///
/// Technical §3.1/§3.3/§5.3. Pure Dart via `package:cryptography` — no
/// native build step (Technical §3.1 note).
library;

import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Raw byte length of an Ed25519 seed, private scalar or public key.
const identityKeyLength = 32;

final Ed25519 _ed25519 = Ed25519();
final X25519 _x25519 = X25519();

/// An Ed25519 key pair for one KERYX identity.
///
/// [seed] is the 32-byte private seed persisted via [IdentityStore]; it
/// is never transmitted. [publicKey] is safe to share (it *is* the
/// identity, Technical §3.1).
class IdentityKeyPair {
  IdentityKeyPair._(this.seed, this.publicKey, this._simpleKeyPair);

  /// Generates a fresh key pair from a cryptographically secure RNG.
  static Future<IdentityKeyPair> generate() async {
    final keyPair = await _ed25519.newKeyPair();
    final data = await keyPair.extract();
    final publicKey = await keyPair.extractPublicKey();
    return IdentityKeyPair._(
      Uint8List.fromList(data.bytes),
      Uint8List.fromList(publicKey.bytes),
      keyPair,
    );
  }

  /// Reconstructs the key pair deterministically from a 32-byte seed
  /// (either a persisted seed or one derived from a recovery phrase,
  /// Technical §3.2).
  static Future<IdentityKeyPair> fromSeed(List<int> seed) async {
    if (seed.length != identityKeyLength) {
      throw ArgumentError.value(
        seed.length,
        'seed.length',
        'must be $identityKeyLength bytes',
      );
    }
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    return IdentityKeyPair._(
      Uint8List.fromList(seed),
      Uint8List.fromList(publicKey.bytes),
      keyPair,
    );
  }

  /// 32-byte private seed. Never leaves the phone (V2-FR-002/D10).
  final Uint8List seed;

  /// 32-byte Ed25519 public key. This is the identity (Technical §3.1).
  final Uint8List publicKey;

  final SimpleKeyPair _simpleKeyPair;

  /// Signs [message], returning the raw 64-byte Ed25519 signature.
  Future<Uint8List> sign(List<int> message) async {
    final signature = await _ed25519.sign(message, keyPair: _simpleKeyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// The X25519 private scalar for this identity, used only for sealed-box
  /// opening (Technical §5.3). This is the standard Ed25519→X25519
  /// "birational map" clamping (libsodium's
  /// `crypto_sign_ed25519_sk_to_curve25519`): SHA-512(seed)[0:32], clamped.
  Future<SimpleKeyPair> toX25519KeyPair() async {
    final scalar = await ed25519SeedToX25519Scalar(seed);
    return _x25519.newKeyPairFromSeed(scalar);
  }
}

/// Verifies a raw Ed25519 [signature] of [message] under [publicKey].
/// Returns `false` for a tampered message, wrong key or malformed
/// signature — never throws for those cases (Technical §3.3).
Future<bool> verifyEd25519(
  List<int> message,
  List<int> signature,
  List<int> publicKey,
) async {
  if (signature.length != 64 || publicKey.length != identityKeyLength) {
    return false;
  }
  try {
    return await _ed25519.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } on Object {
    return false;
  }
}

/// Derives the RFC 7748 X25519 private scalar from an Ed25519 [seed]
/// (SHA-512(seed)[0:32], clamped). Exposed for testing the Ed25519↔X25519
/// birational map in isolation.
Future<Uint8List> ed25519SeedToX25519Scalar(List<int> seed) async {
  final digest = await Sha512().hash(seed);
  final scalar = Uint8List.fromList(digest.bytes.sublist(0, 32));
  scalar[0] &= 248;
  scalar[31] &= 127;
  scalar[31] |= 64;
  return scalar;
}

/// Converts an Ed25519 public key to its Montgomery-form X25519 public
/// key (the u-coordinate), so a sender who only has a recipient's
/// identity key can seal a message to it (Technical §5.3). Throws
/// [FormatException] if [edwardsPublicKey] does not decode to a point on
/// the curve.
Uint8List edwardsPublicKeyToX25519(List<int> edwardsPublicKey) {
  if (edwardsPublicKey.length != identityKeyLength) {
    throw FormatException(
      'Ed25519 public key must be $identityKeyLength bytes',
    );
  }
  final p = _fieldPrime;
  final signBit = (edwardsPublicKey[31] >> 7) & 1;
  final yBytes = Uint8List.fromList(edwardsPublicKey);
  yBytes[31] &= 0x7f;
  final y = _decodeLittleEndian(yBytes) % p;

  final y2 = (y * y) % p;
  final numerator = (y2 - BigInt.one) % p;
  final denominator = (_edwardsD * y2 + BigInt.one) % p;
  final x2 = (numerator * _modInverse(denominator, p)) % p;

  var x = _modPow(x2, (p + BigInt.from(3)) >> 3, p);
  if ((x * x - x2) % p != BigInt.zero) {
    x = (x * _sqrtMinusOne) % p;
  }
  if ((x * x - x2) % p != BigInt.zero) {
    throw const FormatException('not a valid Ed25519 public key');
  }
  if (x == BigInt.zero && signBit == 1) {
    throw const FormatException('not a valid Ed25519 public key');
  }
  if ((x.isOdd ? 1 : 0) != signBit) {
    x = (p - x) % p;
  }

  // Birational map: u = (1 + y) / (1 - y) mod p.
  final oneMinusY = (BigInt.one - y) % p;
  if (oneMinusY == BigInt.zero) {
    throw const FormatException('point has no Montgomery equivalent');
  }
  final u = ((BigInt.one + y) * _modInverse(oneMinusY, p)) % p;
  return _encodeLittleEndian(u, identityKeyLength);
}

final BigInt _fieldPrime = BigInt.two.pow(255) - BigInt.from(19);
final BigInt _edwardsD =
    (-BigInt.from(121665) * _modInverse(BigInt.from(121666), _fieldPrime)) %
    _fieldPrime;
final BigInt _sqrtMinusOne = _modPow(
  BigInt.two,
  (_fieldPrime - BigInt.one) >> 2,
  _fieldPrime,
);

BigInt _modPow(BigInt base, BigInt exponent, BigInt modulus) =>
    base.modPow(exponent, modulus);

BigInt _modInverse(BigInt a, BigInt modulus) =>
    a.modPow(modulus - BigInt.two, modulus);

BigInt _decodeLittleEndian(List<int> bytes) {
  var result = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    result = (result << 8) | BigInt.from(bytes[i]);
  }
  return result;
}

Uint8List _encodeLittleEndian(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  final mask = BigInt.from(0xff);
  for (var i = 0; i < length; i++) {
    out[i] = (v & mask).toInt();
    v = v >> 8;
  }
  return out;
}
