/// RFC 4648 §6 base32, lowercase, no padding.
///
/// Spec-silent pin (TS §8.6 writes only `base32(...)`). Matches the
/// TASK-007 dossier convention so roomId and peerId stay in the same
/// alphabet family. Coordinated by comment, not shared code — rooms/
/// is a different territory. token-svc roomIds are the same alphabet
/// in uppercase; peerId is a different identifier and stays lowercase.
const rfc4648Base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// Encodes [bytes] as unpadded RFC 4648 base32 (lowercase).
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
