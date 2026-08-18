import 'dart:math';
import 'dart:typed_data';

/// Canonical 8-4-4-4-12 lowercase hex form of an RFC 4122 UUID.
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// 16 raw RFC 4122 bytes for a hyphenated UUID string.
///
/// Throws [FormatException] if [canonical] is not the lowercase
/// 8-4-4-4-12 form this package persists.
Uint8List uuidBytes(String canonical) {
  final normalized = canonical.trim().toLowerCase();
  if (!_uuidPattern.hasMatch(normalized)) {
    throw FormatException('Not a canonical UUID: $canonical');
  }
  final hex = normalized.replaceAll('-', '');
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Formats 16 bytes as a lowercase hyphenated UUID. Does not re-stamp
/// version/variant — callers that need a v4 must generate one.
String formatUuid(List<int> bytes) {
  if (bytes.length != 16) {
    throw ArgumentError.value(bytes.length, 'bytes.length', 'UUID is 16 bytes');
  }
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

/// RFC 4122 UUID version 4 (random), variant 1.
String generateUuidV4([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = rng.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return formatUuid(bytes);
}

/// True when [value] is a lowercase hyphenated UUID this package accepts.
bool isCanonicalUuid(String value) => _uuidPattern.hasMatch(value);
