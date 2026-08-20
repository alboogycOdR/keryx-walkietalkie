import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A minimal loopback HTTP server standing in for token-svc, shared by
/// [TokenClient]'s own tests and any test that needs a real `POST /token`
/// round trip underneath a [LinkedController] (no HTTP package dependency
/// exists in this repo to mock against — see `token_client.dart`'s
/// dartdoc — so a real loopback socket is the fake).
class FakeTokenServer {
  FakeTokenServer._(this._server);

  final HttpServer _server;
  Map<String, Object?>? lastRequestBody;
  int statusCode = 200;
  Object? responseBody;
  bool malformedBody = false;

  static Future<FakeTokenServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeTokenServer._(server);
    unawaited(fake._serve());
    return fake;
  }

  Uri get baseUrl => Uri(scheme: 'http', host: 'localhost', port: _server.port);

  Future<void> _serve() async {
    await for (final request in _server) {
      final raw = await utf8.decoder.bind(request).join();
      lastRequestBody = raw.isEmpty ? null : jsonDecode(raw) as Map<String, Object?>;
      request.response.statusCode = statusCode;
      request.response.headers.contentType = ContentType.json;
      if (malformedBody) {
        request.response.write('{not json');
      } else {
        request.response.write(jsonEncode(responseBody));
      }
      await request.response.close();
    }
  }

  Future<void> close() => _server.close(force: true);
}
