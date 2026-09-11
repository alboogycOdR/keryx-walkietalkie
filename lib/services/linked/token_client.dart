import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair;
import 'package:keryx/core/identity/signing.dart' show signRequest;

const _logName = 'keryx.linked';

/// HTTP client for the token service's `POST /token` contract
/// (`token-svc/README.md`, TASK-003). Mints the short-lived LiveKit JWT a
/// [LinkedController] needs to join a room.
///
/// Uses `dart:io`'s [HttpClient] — the same convention as
/// `lib/services/signaling/io_signaling_endpoint.dart` — rather than adding
/// a network package dependency (`pubspec.yaml` is outside this task's
/// `Owned_Paths`).
///
/// Never logs `callsign`, `roomId`, or the returned token — mirrors the
/// token service's own logging policy (TS §8.7).
///
/// v2 (Technical §4.2): when [signer] is supplied, every request carries
/// the `X-Keryx-Sig`/`X-Keryx-Key`/`X-Keryx-Ts` headers TASK-083's
/// `signRequest` computes, so the directory's membership check
/// (`POST /token` — "now checks the signed caller is a member of room_id")
/// has a caller identity to check. `signer == null` keeps the v1,
/// unsigned request shape — callers not yet carrying an identity key
/// (pre-TASK-088 wiring) are unaffected.
class TokenClient {
  TokenClient({
    required Uri baseUrl,
    HttpClient? client,
    Duration? requestTimeout,
    IdentityKeyPair? signer,
  }) : _baseUrl = baseUrl,
       _client = client ?? HttpClient(),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 10),
       _signer = signer;

  final Uri _baseUrl;
  final HttpClient _client;
  final IdentityKeyPair? _signer;

  /// Bounds the whole request/response round trip. FR-045's "relay
  /// unreachable" covers "reachable but wedged", not just outright
  /// connection failure — without this, a token service that accepts the
  /// TCP connection and then hangs blocks the join indefinitely with no
  /// exception and no path to LOCAL fallback.
  final Duration _requestTimeout;

  /// Requests a token for [roomId] (TASK-007's derived roomId) and
  /// [callsign], optionally carrying an Event-QR [eventToken] (TASK-025).
  ///
  /// Throws [TokenRequestException] for any non-200 response, mapping the
  /// service's stable `detail` codes; throws [TokenTransportException] for
  /// network/decoding failures. Never returns a malformed [TokenResponse].
  Future<TokenResponse> requestToken({
    required String roomId,
    required String callsign,
    String? eventToken,
  }) async {
    final uri = resolveTokenUri();
    final bodyJson = jsonEncode({
      'room_id': roomId,
      'callsign': callsign,
      'event_token': eventToken,
    });
    final body = utf8.encode(bodyJson);

    late final HttpClientRequest request;
    late final HttpClientResponse response;
    try {
      request = await _client.postUrl(uri).timeout(_requestTimeout);
      request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      final signer = _signer;
      if (signer != null) {
        final signed = await signRequest(
          keyPair: signer,
          method: 'POST',
          path: uri.path,
          body: bodyJson,
        );
        for (final entry in signed.toHeaders().entries) {
          request.headers.set(entry.key, entry.value);
        }
      }
      request.add(body);
      response = await request.close().timeout(_requestTimeout);
    } on TimeoutException catch (error, stack) {
      developer.log('token request timed out', name: _logName, error: error, stackTrace: stack);
      throw TokenTransportException('token service did not respond within $_requestTimeout: $error');
    } on Object catch (error, stack) {
      developer.log('token request transport failure', name: _logName, error: error, stackTrace: stack);
      throw TokenTransportException('failed to reach token service: $error');
    }

    final String rawBody;
    try {
      rawBody = await response.transform(utf8.decoder).join().timeout(_requestTimeout);
    } on TimeoutException catch (error, stack) {
      developer.log('token response body timed out', name: _logName, error: error, stackTrace: stack);
      throw TokenTransportException('token service response body timed out: $error');
    }

    if (response.statusCode != 200) {
      final detail = _extractDetail(rawBody);
      developer.log(
        'token request refused: status=${response.statusCode} detail=$detail',
        name: _logName,
      );
      throw TokenRequestException(statusCode: response.statusCode, detail: detail);
    }

    final Map<String, Object?> json;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('token response was not a JSON object');
      }
      json = decoded;
    } on FormatException catch (error) {
      throw TokenTransportException('malformed token response body: $error');
    }

    final token = json['token'];
    final identity = json['identity'];
    final ttlSeconds = json['ttl_seconds'];
    if (token is! String || token.isEmpty) {
      throw const TokenTransportException('token response missing/empty "token"');
    }
    if (identity is! String || identity.isEmpty) {
      throw const TokenTransportException('token response missing/empty "identity"');
    }
    if (ttlSeconds is! num || ttlSeconds <= 0) {
      throw const TokenTransportException('token response missing/invalid "ttl_seconds"');
    }

    return TokenResponse(
      token: token,
      identity: identity,
      ttl: Duration(seconds: ttlSeconds.toInt()),
    );
  }

  /// Resolves the `/token` endpoint against [_baseUrl] without discarding
  /// any path prefix the base URL carries (e.g. `https://host/api` must
  /// resolve to `https://host/api/token`, not `https://host/token`).
  ///
  /// If the last non-empty path segment is already `token` — the Caddy
  /// route, which `KeryxSettings.resolvedTokenServiceUrl` already yields
  /// for a derived default — the URI is returned as-is so the client does
  /// not POST `/token/token`.
  Uri resolveTokenUri() {
    final segments = _baseUrl.pathSegments.where((s) => s.isNotEmpty);
    if (segments.isNotEmpty && segments.last == 'token') {
      return _baseUrl;
    }
    final base = _baseUrl.path.endsWith('/') ? _baseUrl : _baseUrl.replace(path: '${_baseUrl.path}/');
    return base.resolve('token');
  }

  static String? _extractDetail(String rawBody) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, Object?>) {
        final detail = decoded['detail'];
        if (detail is String) return detail;
      }
    } on FormatException {
      // fall through — non-JSON error body, no detail extractable.
    }
    return null;
  }

  void close() => _client.close(force: true);
}

/// Successful `POST /token` result.
class TokenResponse {
  const TokenResponse({required this.token, required this.identity, required this.ttl});

  /// The short-lived LiveKit JWT.
  final String token;

  /// `{callsign}#{8 hex chars}` per token-svc's identity contract.
  final String identity;

  final Duration ttl;
}

/// The token service refused the request. [detail] is one of the stable
/// codes documented in `token-svc/README.md` (`invalid_request`,
/// `expired_event_token`, `invalid_event_token`, `rate_limited`) when the
/// service returned one, else `null`.
class TokenRequestException implements Exception {
  const TokenRequestException({required this.statusCode, required this.detail});

  final int statusCode;
  final String? detail;

  @override
  String toString() => 'TokenRequestException(status: $statusCode, detail: $detail)';
}

/// Network failure, timeout, or a response that could not be parsed as a
/// valid [TokenResponse] — distinct from [TokenRequestException] so callers
/// can tell "the service said no" from "we couldn't talk to the service".
class TokenTransportException implements Exception {
  const TokenTransportException(this.message);

  final String message;

  @override
  String toString() => 'TokenTransportException($message)';
}
