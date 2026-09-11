/// Thin WebSocket abstraction so [PresenceClient] is unit-testable against
/// a fake instead of a real socket — mirrors the [LiveKitAdapter] /
/// [RtcAdapter] split elsewhere in `lib/services/**`.
library;

import 'dart:async';
import 'dart:io';

abstract class PresenceTransport {
  Future<PresenceSocket> connect({required Uri url, required Map<String, String> headers});
}

abstract class PresenceSocket {
  /// Raw text frames from the server.
  Stream<String> get messages;

  /// Fires once the socket closes, for any reason (server hangup, network
  /// drop, or a local [close] call) — the single signal [PresenceClient]'s
  /// reconnect loop needs, regardless of cause.
  Future<void> get done;

  void send(String data);

  Future<void> close();
}

/// Production [PresenceTransport]: `dart:io`'s [WebSocket.connect] with the
/// three signed headers carried as the WS upgrade request's headers
/// (Technical §4.2: "Upgrade with the same signed headers").
class IoPresenceTransport implements PresenceTransport {
  const IoPresenceTransport();

  @override
  Future<PresenceSocket> connect({required Uri url, required Map<String, String> headers}) async {
    final socket = await WebSocket.connect(url.toString(), headers: headers);
    return _IoPresenceSocket(socket);
  }
}

class _IoPresenceSocket implements PresenceSocket {
  _IoPresenceSocket(this._socket) {
    _messages = _socket
        .map((event) => event is String ? event : String.fromCharCodes(event as List<int>))
        .asBroadcastStream();
    _doneCompleter = Completer<void>();
    _messages.listen(
      null,
      onDone: () {
        if (!_doneCompleter.isCompleted) _doneCompleter.complete();
      },
      onError: (Object _) {
        if (!_doneCompleter.isCompleted) _doneCompleter.complete();
      },
    );
  }

  final WebSocket _socket;
  late final Stream<String> _messages;
  late final Completer<void> _doneCompleter;

  @override
  Stream<String> get messages => _messages;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  void send(String data) => _socket.add(data);

  @override
  Future<void> close() => _socket.close();
}
