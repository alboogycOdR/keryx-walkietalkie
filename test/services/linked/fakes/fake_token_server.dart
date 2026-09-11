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
  Map<String, String>? lastRequestHeaders;
  int statusCode = 200;
  Object? responseBody;
  bool malformedBody = false;

  /// v2 (Technical §4.2): when true, a request missing any of
  /// `X-Keryx-Sig`/`X-Keryx-Key`/`X-Keryx-Ts` is refused with 401 —
  /// simulates the directory's "signed caller" gate on `POST /token`.
  bool requireSignature = false;

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
      lastRequestHeaders = {
        for (final name in const ['x-keryx-sig', 'x-keryx-key', 'x-keryx-ts'])
          if (request.headers.value(name) != null) name: request.headers.value(name)!,
      };
      if (requireSignature &&
          (request.headers.value('x-keryx-sig') == null ||
              request.headers.value('x-keryx-key') == null ||
              request.headers.value('x-keryx-ts') == null)) {
        request.response.statusCode = 401;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'detail': 'unsigned_request'}));
        await request.response.close();
        continue;
      }
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
