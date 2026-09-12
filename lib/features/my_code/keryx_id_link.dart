import 'dart:convert';
import 'dart:typed_data';

import 'package:keryx/core/identity/peer_id.dart';

/// Encode/decode of the v2 ID QR and share link (Technical §3.1, V2-FR-004).
///
/// QR: `keryx://id?v=1&c=<callsign>&k=<base64url(publicKey)>`
/// HTTPS: `https://keryx.app/c/<callsign>-<code>?k=<base64url(publicKey)>`
/// Display: `<CALLSIGN>·<CODE>`
class KeryxIdLink {
  const KeryxIdLink({required this.callsign, required this.publicKey});

  final String callsign;
  final Uint8List publicKey;

  /// 4-character short code from the public key (Technical §3.1).
  String get shortCode => deriveShortCode(publicKey);

  /// `<CALLSIGN>·<CODE>`
  String get displayId => '$callsign·$shortCode';

  /// Unpadded base64url of the 32-byte Ed25519 public key.
  String get encodedKey => encodeUnpaddedBase64Url(publicKey);

  /// QR payload. Carries the public key so a scan verifies locally.
  String get qrPayload {
    return Uri(
      scheme: 'keryx',
      host: 'id',
      queryParameters: <String, String>{
        'v': '1',
        'c': callsign,
        'k': encodedKey,
      },
    ).toString();
  }

  /// Shareable HTTPS link (Technical §3.1).
  String get shareUrl {
    return Uri(
      scheme: 'https',
      host: 'keryx.app',
      path: '/c/$callsign-$shortCode',
      queryParameters: <String, String>{'k': encodedKey},
    ).toString();
  }

  /// Parses a QR payload or an HTTPS share URL. Throws [FormatException]
  /// when the URI is the wrong shape, the version is not `1`, or the key
  /// is not 32 decoded bytes.
  static KeryxIdLink parse(String raw) {
    final uri = Uri.parse(raw);
    if (uri.scheme == 'keryx' && uri.host == 'id') {
      return _fromQuery(uri.queryParameters, callsignOverride: null);
    }
    if (uri.scheme == 'https' &&
        uri.host == 'keryx.app' &&
        uri.pathSegments.length == 2 &&
        uri.pathSegments.first == 'c') {
      final slug = uri.pathSegments[1];
      final dash = slug.lastIndexOf('-');
      if (dash <= 0 || dash == slug.length - 1) {
        throw const FormatException('share link missing callsign-code');
      }
      final callsign = slug.substring(0, dash);
      return _fromQuery(uri.queryParameters, callsignOverride: callsign);
    }
    throw const FormatException('not a KERYX ID link');
  }

  static KeryxIdLink _fromQuery(
    Map<String, String> query, {
    required String? callsignOverride,
  }) {
    final version = query['v'] ?? '1';
    if (version != '1') {
      throw FormatException('unsupported ID link version: $version');
    }
    final callsign = callsignOverride ?? query['c'];
    final encoded = query['k'];
    if (callsign == null || callsign.isEmpty) {
      throw const FormatException('ID link missing callsign');
    }
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('ID link missing public key');
    }
    late final Uint8List key;
    try {
      key = decodeUnpaddedBase64Url(encoded);
    } on FormatException {
      throw const FormatException('ID link public key is not valid base64url');
    }
    if (key.length != 32) {
      throw FormatException(
        'ID link public key must be 32 bytes, got ${key.length}',
      );
    }
    return KeryxIdLink(callsign: callsign, publicKey: key);
  }
}

String encodeUnpaddedBase64Url(List<int> bytes) {
  final padded = base64Url.encode(bytes);
  final padStart = padded.indexOf('=');
  return padStart == -1 ? padded : padded.substring(0, padStart);
}

Uint8List decodeUnpaddedBase64Url(String encoded) {
  var padded = encoded;
  final mod = padded.length % 4;
  if (mod != 0) {
    padded = padded.padRight(padded.length + (4 - mod), '=');
  }
  return Uint8List.fromList(base64Url.decode(padded));
}
