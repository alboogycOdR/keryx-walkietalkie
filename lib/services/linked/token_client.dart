import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

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
class TokenClient {
  TokenClient({required Uri baseUrl, HttpClient? client})
    : _baseUrl = baseUrl,
      _client = client ?? HttpClient();

  final Uri _baseUrl;
  final HttpClient _client;

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
    final uri = _baseUrl.resolve('/token');
    final body = utf8.encode(
      jsonEncode({
        'room_id': roomId,
        'callsign': callsign,
        'event_token': eventToken,
      }),
    );

    late final HttpClientRequest request;
    late final HttpClientResponse response;
    try {
      request = await _client.postUrl(uri);
      request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
      request.add(body);
      response = await request.close();
    } on Object catch (error, stack) {
      developer.log('token request transport failure', name: _logName, error: error, stackTrace: stack);
      throw TokenTransportException('failed to reach token service: $error');
    }

    final rawBody = await response.transform(utf8.decoder).join();

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
