import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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
