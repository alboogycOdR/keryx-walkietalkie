import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' show KeyPairType, SimplePublicKey, X25519;
import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair, edwardsPublicKeyToX25519;

import 'rfc4648_base32.dart';
import 'scrypt_stretch.dart';

export 'scrypt_stretch.dart' show keryxContext, KeyedScrypt;

/// Keyed-channel HMAC prefix from TS §8.7 (`"PRV"`).
const keyedPrefix = 'PRV';

/// Length of a §8.7 roomId (`b32(...)[:16]`).
const roomIdLength = 16;

/// token-svc / ORCH ruling (d): RFC 4648 uppercase, unpadded.
final roomIdPattern = RegExp(r'^[A-Z2-7]{16}$');

/// `keyed: roomId = b32(HMAC-SHA256("KERYX.v1", "PRV" | scrypt(passphrase)))[:16]`
///
/// Spec-silent pin, proposed for ORCH ratification:
/// scrypt output is 32 raw bytes (see [KeyedScrypt]); the HMAC message
/// is the three ASCII bytes `PRV` concatenated with those 32 bytes —
/// no pipe separator, because the stretch is binary. [passphrase] is
/// UTF-8 encoded and is **not** trimmed (leading/trailing spaces are
/// entropy). Empty passphrases are rejected.
///
/// The passphrase never leaves this function: no I/O, no logging.
/// The server sees only the resulting 16-character room hash.
String deriveKeyed({required String passphrase}) {
  if (passphrase.isEmpty) {
    throw ArgumentError.value(passphrase, 'passphrase', 'must be non-empty');
  }
  final stretched = stretchPassphrase(passphrase);
  final message = Uint8List(keyedPrefix.length + stretched.length);
  message.setAll(0, utf8.encode(keyedPrefix));
  message.setAll(keyedPrefix.length, stretched);
  return _roomIdFromHmac(message);
}

/// True when [value] is a 16-character RFC 4648 uppercase roomId.
bool isRoomId(String value) => roomIdPattern.hasMatch(value);

/// v2 group room (Technical §5.1): `roomId = deriveKeyed(base64(groupSecret))`.
///
/// [groupSecret] is the group's 32 random bytes (minted once by the
/// creator, Technical §5.1); the same secret always yields the same
/// roomId, and a rotated secret (Technical §5.3) yields a different one.
/// The secret never appears in the room ID — it goes through [deriveKeyed]'s
/// scrypt stretch exactly like a passphrase.
String deriveGroupRoom(List<int> groupSecret) {
  if (groupSecret.isEmpty) {
    throw ArgumentError.value(groupSecret, 'groupSecret', 'must be non-empty');
  }
  return deriveKeyed(passphrase: base64Encode(groupSecret));
}

/// v2 1:1 room (Technical §5.4): `roomId = deriveKeyed(base64(x25519(myPriv, theirPub)))`.
///
/// [myKeyPair] is the caller's own identity key pair; [theirEdwardsPublicKey]
/// is the other party's 32-byte Ed25519 identity public key. X25519 ECDH is
/// symmetric — `sharedSecret(A.priv, B.pub) == sharedSecret(B.priv, A.pub)` —
/// so both participants derive the identical roomId regardless of which
/// side computes it first; a dedicated test proves this rather than relying
/// on the property of the underlying primitive alone. No server state is
/// needed (Technical §5.4).
Future<String> deriveDirectRoom({
  required IdentityKeyPair myKeyPair,
  required List<int> theirEdwardsPublicKey,
}) async {
  final myX25519 = await myKeyPair.toX25519KeyPair();
  final theirX25519PublicKey = edwardsPublicKeyToX25519(theirEdwardsPublicKey);
  final shared = await X25519().sharedSecretKey(
    keyPair: myX25519,
    remotePublicKey: SimplePublicKey(
      theirX25519PublicKey,
      type: KeyPairType.x25519,
    ),
  );
  final sharedBytes = await shared.extractBytes();
  return deriveKeyed(passphrase: base64Encode(sharedBytes));
}

String _roomIdFromHmac(List<int> message) {
  final digest = Hmac(sha256, utf8.encode(keryxContext)).convert(message);
  final encoded = encodeRfc4648Base32(digest.bytes);
  return encoded.substring(0, roomIdLength);
}

