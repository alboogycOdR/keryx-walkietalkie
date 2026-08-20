import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'signaling_channel.dart';

/// Production LAN endpoint: `HttpServer` + WebSocket upgrade.
///
/// Binds [lanBindAddress] (`anyIPv4`) on an ephemeral port so the
/// socket is reachable on the LAN, not loopback-only (TS §8.3 step 2).
class IoSignalingEndpoint implements SignalingEndpoint {
  IoSignalingEndpoint({InternetAddress? bindAddress})
    : bindAddress = bindAddress ?? lanBindAddress;

  /// Loopback-free LAN bind. Never `InternetAddress.loopbackIPv4`.
  static final InternetAddress lanBindAddress = InternetAddress.anyIPv4;

  final InternetAddress bindAddress;
  final _incoming = StreamController<SignalingChannel>.broadcast();

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _sub;
  bool _closed = false;

  @override
  int get port => _server?.port ?? 0;

  @override
  Stream<SignalingChannel> get incoming => _incoming.stream;

  @override
  Future<void> bind() async {
    if (_closed) throw StateError('endpoint is closed');
    if (_server != null) return;
    if (bindAddress.isLoopback) {
      throw StateError(
        'refusing loopback bind; LOCAL signaling is LAN-only (TS §8.3)',
      );
    }
    _server = await HttpServer.bind(bindAddress, 0);
    _sub = _server!.listen(
      _onRequest,
      onError: (Object e, StackTrace st) {
        developer.log(
          'signaling http error: $e',
          name: 'keryx.signaling',
          stackTrace: st,
        );
      },
    );
    developer.log(
      'signaling bound ${bindAddress.address}:$port',
      name: 'keryx.signaling',
    );
  }

  @override
  Future<SignalingChannel> connect(String host, int port) async {
    if (_closed) throw StateError('endpoint is closed');
    if (host.isEmpty) {
      throw ArgumentError.value(host, 'host', 'must be non-empty');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    final ws = await WebSocket.connect('ws://$host:$port/');
    return _IoChannel(ws, '$host:$port');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    await _server?.close(force: true);
    _server = null;
    await _incoming.close();
  }

  Future<void> _onRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    try {
      final ws = await WebSocketTransformer.upgrade(request);
      final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      if (_closed || _incoming.isClosed) {
        await ws.close();
        return;
      }
      _incoming.add(_IoChannel(ws, remote));
    } catch (e, st) {
      developer.log(
        'websocket upgrade failed: $e',
        name: 'keryx.signaling',
        stackTrace: st,
      );
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on Object {
        // Already hijacked or closed.
      }
    }
  }
}

class _IoChannel implements SignalingChannel {
  _IoChannel(this._ws, this.remoteLabel) {
    _ws.listen(
      (dynamic data) {
        if (data is String) {
          if (!_incoming.isClosed) _incoming.add(data);
        }
      },
      onError: (Object e, StackTrace st) {
        developer.log(
          'signaling socket error: $e',
          name: 'keryx.signaling',
          stackTrace: st,
        );
        _incoming.addError(e, st);
      },
      onDone: () {
        if (!_incoming.isClosed) _incoming.close();
      },
      cancelOnError: false,
    );
  }

  final WebSocket _ws;
  final _incoming = StreamController<String>();

  @override
  final String remoteLabel;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  void send(String text) {
    if (_ws.readyState != WebSocket.open) return;
    _ws.add(text);
  }

  @override
  Future<void> close() async {
    await _ws.close();
    if (!_incoming.isClosed) await _incoming.close();
  }
}
