import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A minimal loopback HTTP server standing in for the v2 directory
/// (`token-svc`), for the same reason `test/services/linked/fakes/fake_token_server.dart`
/// exists: there is no HTTP mocking package in this repo, and
/// `DirectoryClient` is a thin `dart:io` pass-through by design (mirrors
/// `TokenClient`).
class FakeDirectoryServer {
  FakeDirectoryServer._(this._server);

  final HttpServer _server;
  final List<RecordedDirectoryRequest> requests = [];

  /// Set by a test to control the response for the next (or every)
  /// request; defaults to `200 {}` for anything not otherwise configured.
  FutureOr<DirectoryFakeResponse> Function(RecordedDirectoryRequest request)? responder;

  static Future<FakeDirectoryServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeDirectoryServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Uri get baseUrl => Uri(scheme: 'http', host: 'localhost', port: _server.port);

  Future<void> _serve() async {
    await for (final request in _server) {
      final raw = await utf8.decoder.bind(request).join();
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        if (values.isNotEmpty) headers[name.toLowerCase()] = values.first;
      });
      final recorded = RecordedDirectoryRequest(
        method: request.method,
        path: request.uri.path,
        headers: headers,
        rawBody: raw,
      );
      requests.add(recorded);

      final resp = responder != null
          ? await responder!(recorded)
          : const DirectoryFakeResponse(statusCode: 200, body: {});
      request.response.statusCode = resp.statusCode;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(resp.body));
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}

class RecordedDirectoryRequest {
  const RecordedDirectoryRequest({
    required this.method,
    required this.path,
    required this.headers,
    required this.rawBody,
  });

  final String method;
  final String path;
  final Map<String, String> headers;
  final String rawBody;

  Map<String, Object?>? get bodyJson {
    if (rawBody.isEmpty) return null;
    final decoded = jsonDecode(rawBody);
    return decoded is Map<String, Object?> ? decoded : null;
  }
}

class DirectoryFakeResponse {
  const DirectoryFakeResponse({required this.statusCode, required this.body});
  final int statusCode;
  final Map<String, Object?> body;
}
