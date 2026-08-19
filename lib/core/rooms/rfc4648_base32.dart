/// RFC 4648 §6 base32, uppercase, no padding.
///
/// ORCH ruling (follow-up d, 2026-08-19): roomId is RFC 4648
/// uppercase-unpadded (`^[A-Z2-7]{16}$`), matching token-svc's
/// already-deployed validator. peerId (TASK-009) uses the same
/// alphabet in lowercase — rooms/ does not import identity/; this
/// encoder is a local copy so territories stay disjoint.
const rfc4648Base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Encodes [bytes] as unpadded RFC 4648 base32 (uppercase).
String encodeRfc4648Base32(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final out = StringBuffer();
  var buffer = 0;
  var bitsLeft = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | (byte & 0xff);
    bitsLeft += 8;
    while (bitsLeft >= 5) {
      bitsLeft -= 5;
      out.write(rfc4648Base32Alphabet[(buffer >> bitsLeft) & 0x1f]);
    }
  }
  if (bitsLeft > 0) {
    out.write(rfc4648Base32Alphabet[(buffer << (5 - bitsLeft)) & 0x1f]);
  }
  return out.toString();
}
