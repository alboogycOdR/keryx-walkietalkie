import 'package:crypto/crypto.dart';

import 'install_uuid.dart';
import 'rfc4648_base32.dart';

/// Length of the peerId (`base32(sha256(x))[:10]`).
const peerIdLength = 10;

/// Length of the short code shown as `<CALLSIGN>·<CODE>` (Technical §3.1).
const shortCodeLength = 4;

/// Derives a peerId, `base32(SHA-256(x))[:10]`.
///
/// The v2 identity (Technical §3.1) input is the 32-byte Ed25519 public
/// key ([List<int>]) — pass it here for every new call site.
///
/// A [String] is also accepted and hashed as a legacy install-UUID
/// (the original v1 derivation, hashing the 16 raw RFC 4122 bytes) purely
/// so `test/simulation/sim_peer.dart` — outside this task's `Owned_Paths`,
/// a soak-test harness for the floor engine that Technical §1 keeps
/// as-is — keeps compiling and producing the same election-simulation
/// peerIds it always has. New identity code should never pass a String.
String derivePeerId(Object publicKeyOrLegacyUuid) =>
    _digest(publicKeyOrLegacyUuid).substring(0, peerIdLength);

/// Derives the 4-character short code from the same digest as [derivePeerId]
/// (Technical §3.1): `base32(sha256(publicKey))[10:14]`.
String deriveShortCode(List<int> publicKey) =>
    _digest(publicKey).substring(peerIdLength, peerIdLength + shortCodeLength);

String _digest(Object publicKeyOrLegacyUuid) {
  final bytes = publicKeyOrLegacyUuid is String
      ? uuidBytes(publicKeyOrLegacyUuid)
      : publicKeyOrLegacyUuid as List<int>;
  return encodeRfc4648Base32(sha256.convert(bytes).bytes);
}

/// True when [value] is a 10-character RFC 4648 lowercase peerId.
bool isPeerId(String value) {
  if (value.length != peerIdLength) return false;
  for (var i = 0; i < value.length; i++) {
    if (!rfc4648Base32Alphabet.contains(value[i])) return false;
  }
  return true;
}
