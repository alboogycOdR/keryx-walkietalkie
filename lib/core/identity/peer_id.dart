import 'package:crypto/crypto.dart';

import 'rfc4648_base32.dart';

/// Length of the peerId (`base32(sha256(publicKey))[:10]`).
const peerIdLength = 10;

/// Length of the short code shown as `<CALLSIGN>·<CODE>` (Technical §3.1).
const shortCodeLength = 4;

/// Derives the peerId from an Ed25519 public key.
///
/// `peerId = base32(SHA-256(publicKey))[:10]` (Technical §3.1). Re-pointed
/// from the v1 install-UUID input to the v2 identity public key; the output
/// shape (10-char unpadded RFC 4648 base32) is unchanged so every existing
/// consumer of a `PeerId` string keeps working (TASK-020/022 election keys
/// stay stable in shape, if not in value, across the v1→v2 migration).
String derivePeerId(List<int> publicKey) => _digest(publicKey).substring(
  0,
  peerIdLength,
);

/// Derives the 4-character short code from the same digest as [derivePeerId]
/// (Technical §3.1): `base32(sha256(publicKey))[10:14]`.
String deriveShortCode(List<int> publicKey) => _digest(
  publicKey,
).substring(peerIdLength, peerIdLength + shortCodeLength);

String _digest(List<int> publicKey) =>
    encodeRfc4648Base32(sha256.convert(publicKey).bytes);

/// True when [value] is a 10-character RFC 4648 lowercase peerId.
bool isPeerId(String value) {
  if (value.length != peerIdLength) return false;
  for (var i = 0; i < value.length; i++) {
    if (!rfc4648Base32Alphabet.contains(value[i])) return false;
  }
  return true;
}
