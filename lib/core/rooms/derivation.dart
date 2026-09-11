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

/// Numbered-channel domain, matching FR-002 / settings (CH 01–99).
const minChannel = 1;
const maxChannel = 99;

/// Privacy-code domain, matching FR-002 (00–38; `00` = open).
const minPrivacyCode = 0;
const maxPrivacyCode = 38;

/// `numbered: roomId = b32(HMAC-SHA256("KERYX.v1", region | ch | code))[:16]`
///
/// Spec-silent pin, proposed for ORCH ratification:
/// the HMAC message is UTF-8 `"$region|$ch|$code"` with [channel] and
/// [code] zero-padded to two decimal digits (`7` → `"07"`, `0` → `"00"`).
/// [region] is used as supplied after trim; it must be non-empty and
/// must not contain `|` (the field separator). Case-sensitive, so
/// `"za-cpt"` and `"ZA-cpt"` are different rooms (FR-008 partitions
/// by the salt the user actually set).
///
/// HMAC key is UTF-8 `"KERYX.v1"`. Digest is RFC 4648 uppercase
/// unpadded base32, first 16 characters.
///
/// **v2 (Technical §6.2) marks this for deletion** — numbered channels are
/// replaced by [deriveGroupRoom]/[deriveDirectRoom]. It is *retained* here
/// only because `lib/services/session/radio_session_controller.dart`
/// (TASK-088's `Owned_Paths`) and `lib/features/event_qr/event_link.dart`
/// (TASK-094's `Owned_Paths`) still call it and are outside this task's
/// territory (Technical §10: item 4, this task, precedes items 5/11 which
/// migrate/delete those callers). Do not add new callers.
String deriveNumbered({
  required String region,
  required int channel,
  required int code,
}) {
  final canonicalRegion = _canonicalRegion(region);
  if (channel < minChannel || channel > maxChannel) {
    throw ArgumentError.value(
      channel,
      'channel',
      'must be $minChannel–$maxChannel',
    );
  }
  if (code < minPrivacyCode || code > maxPrivacyCode) {
    throw ArgumentError.value(
      code,
      'code',
      'must be $minPrivacyCode–$maxPrivacyCode',
    );
  }
  final message = utf8.encode(
    '$canonicalRegion|${_twoDigits(channel)}|${_twoDigits(code)}',
  );
  return _roomIdFromHmac(message);
}

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

String _canonicalRegion(String region) {
  final trimmed = region.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(region, 'region', 'must be non-empty');
  }
  if (trimmed.contains('|')) {
    throw ArgumentError.value(
      region,
      'region',
      'must not contain "|" (field separator)',
    );
  }
  return trimmed;
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
