/// Directory-request signing (Technical §3.3): every mutating call carries
/// `X-Keryx-Sig/Key/Ts`, computed over `sha256(method|path|body|timestamp)`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'keys.dart';

/// Default replay/staleness window (Technical §3.3): the server rejects
/// timestamps more than 120 s old.
const signingWindowSeconds = 120;

/// The three headers a signed directory request carries.
class SignedRequestHeaders {
  const SignedRequestHeaders({
    required this.signatureBase64,
    required this.publicKeyBase64,
    required this.timestamp,
  });

  final String signatureBase64;
  final String publicKeyBase64;
  final int timestamp;

  Map<String, String> toHeaders() => <String, String>{
    'X-Keryx-Sig': signatureBase64,
    'X-Keryx-Key': publicKeyBase64,
    'X-Keryx-Ts': timestamp.toString(),
  };
}

Uint8List _canonicalDigest({
  required String method,
  required String path,
  required String body,
  required int timestamp,
}) {
  final payload = '${method.toUpperCase()}|$path|$body|$timestamp';
  return Uint8List.fromList(sha256.convert(utf8.encode(payload)).bytes);
}

/// Signs one request with the local identity's [keyPair]. [nowUnixSeconds]
/// defaults to the current time and is a seam for deterministic tests.
Future<SignedRequestHeaders> signRequest({
  required IdentityKeyPair keyPair,
  required String method,
  required String path,
  String body = '',
  int? nowUnixSeconds,
}) async {
  final ts = nowUnixSeconds ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  final digest = _canonicalDigest(
    method: method,
    path: path,
    body: body,
    timestamp: ts,
  );
  final signature = await keyPair.sign(digest);
  return SignedRequestHeaders(
    signatureBase64: base64Encode(signature),
    publicKeyBase64: base64Encode(keyPair.publicKey),
    timestamp: ts,
  );
}

/// Why [verifySignedRequest] rejected a request. Mirrors the enumerated
/// directory error codes (Technical §3.3/§4.2) without depending on the
/// (not-yet-built) directory client package.
enum SignedRequestRejection { staleTimestamp, badSignature }

/// The outcome of verifying a signed request locally.
sealed class SignedRequestVerification {
  const SignedRequestVerification();
}

class SignedRequestAccepted extends SignedRequestVerification {
  const SignedRequestAccepted();
}

class SignedRequestRejected extends SignedRequestVerification {
  const SignedRequestRejected(this.reason);
  final SignedRequestRejection reason;
}

/// Verifies a request against the enumerated rules (Technical §3.3): a
/// timestamp more than [windowSeconds] away from [nowUnixSeconds] is
/// stale; otherwise the signature must verify over the same canonical
/// payload the sender signed — a tampered body or wrong key fails here.
///
/// This does not implement the server's replay-nonce cache (Redis, §3.3);
/// that lives in the directory service, not this client-side helper.
Future<SignedRequestVerification> verifySignedRequest({
  required SignedRequestHeaders headers,
  required String method,
  required String path,
  required String body,
  required int nowUnixSeconds,
  int windowSeconds = signingWindowSeconds,
}) async {
  if ((nowUnixSeconds - headers.timestamp).abs() > windowSeconds) {
    return const SignedRequestRejected(
      SignedRequestRejection.staleTimestamp,
    );
  }
  final digest = _canonicalDigest(
    method: method,
    path: path,
    body: body,
    timestamp: headers.timestamp,
  );
  final ok = await verifyEd25519(
    digest,
    base64Decode(headers.signatureBase64),
    base64Decode(headers.publicKeyBase64),
  );
  if (!ok) {
    return const SignedRequestRejected(SignedRequestRejection.badSignature);
  }
  return const SignedRequestAccepted();
}
