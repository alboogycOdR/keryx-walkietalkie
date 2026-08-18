import 'package:crypto/crypto.dart';

import 'install_uuid.dart';
import 'rfc4648_base32.dart';

/// Length of the §8.6 peerId (`base32(...)[:10]`).
const peerIdLength = 10;

/// Derives the normative §8.6 peerId from an install-time UUID.
///
/// `peerId = base32(SHA-256(installUUID))[:10]`
///
/// [installUuid] is the canonical hyphenated string persisted at first
/// run. The hash input is the 16 raw RFC 4122 bytes, not the UTF-8
/// text of the hyphenated form — two string spellings of the same
/// UUID (case, braces) would otherwise fork the identity. Spec-silent;
/// pinned here so TASK-020/022 election keys stay stable.
String derivePeerId(String installUuid) {
  final digest = sha256.convert(uuidBytes(installUuid)).bytes;
  final encoded = encodeRfc4648Base32(digest);
  return encoded.substring(0, peerIdLength);
}

/// True when [value] is a 10-character RFC 4648 lowercase peerId.
bool isPeerId(String value) {
  if (value.length != peerIdLength) return false;
  for (var i = 0; i < value.length; i++) {
    if (!rfc4648Base32Alphabet.contains(value[i])) return false;
  }
  return true;
}
