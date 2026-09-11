/// Directory-specific request signing (Technical §3.3, contract note in
/// `token-svc/openapi-v2.yaml`'s `info.description`).
///
/// TASK-083's `signRequest` (`lib/core/identity/signing.dart`) computes the
/// correct Ed25519 signature over the correct canonical bytes, but emits
/// `X-Keryx-Key` as standard base64 (padded). The v2 contract's canonical
/// wire form is *unpadded base64url* — the server accepts both, but the
/// canonical form is what `token-svc/app/encoding.py::b64url_encode` emits
/// and what a future non-Dart client would produce. Per this task's
/// Acceptance Criteria, that re-encoding happens here (inside
/// `lib/services/directory/**`) rather than by editing
/// `lib/core/identity/**` — TASK-083's helper stays byte-for-byte the
/// contract it already has, and this directory-only wrapper reuses its
/// signature/timestamp verbatim and only swaps the key header's encoding.
library;

import 'dart:convert';

import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair;
import 'package:keryx/core/identity/signing.dart' show signRequest;

/// Signs one directory request and returns headers ready for
/// `HttpClientRequest.headers.set`/WebSocket upgrade headers — same three
/// header names as TASK-083's helper, but `X-Keryx-Key` unpadded base64url.
Future<Map<String, String>> signedDirectoryHeaders({
  required IdentityKeyPair keyPair,
  required String method,
  required String path,
  String body = '',
  int? nowUnixSeconds,
}) async {
  final signed = await signRequest(
    keyPair: keyPair,
    method: method,
    path: path,
    body: body,
    nowUnixSeconds: nowUnixSeconds,
  );
  return {
    'X-Keryx-Sig': signed.signatureBase64,
    'X-Keryx-Key': unpaddedBase64Url(keyPair.publicKey),
    'X-Keryx-Ts': signed.timestamp.toString(),
  };
}

/// Unpadded base64url of [bytes] — `token-svc/app/encoding.py::b64url_encode`'s
/// Dart-side counterpart.
String unpaddedBase64Url(List<int> bytes) {
  final padded = base64Url.encode(bytes);
  final padStart = padded.indexOf('=');
  return padStart == -1 ? padded : padded.substring(0, padStart);
}
