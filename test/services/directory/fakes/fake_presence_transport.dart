import 'dart:async';

import 'package:keryx/services/directory/presence_transport.dart';

/// In-memory [PresenceTransport] for unit tests. Mirrors
/// `test/services/linked/fakes/fake_livekit_adapter.dart`'s shape.
class FakePresenceTransport implements PresenceTransport {
  FakePresenceTransport({this.onConnect});

  /// Optional hook so a test can throw (simulate a connect failure) or
  /// return a specific [FakePresenceSocket].
  final FakePresenceSocket Function(Uri url, Map<String, String> headers)? onConnect;

  final List<({Uri url, Map<String, String> headers})> connectCalls = [];
  FakePresenceSocket? lastSocket;

  @override
  Future<PresenceSocket> connect({required Uri url, required Map<String, String> headers}) async {
    connectCalls.add((url: url, headers: headers));
    final socket = onConnect != null ? onConnect!(url, headers) : FakePresenceSocket();
    lastSocket = socket;
    return socket;
  }
}

class FakePresenceSocket implements PresenceSocket {
  final _messages = StreamController<String>.broadcast(sync: true);
  final _doneCompleter = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    closed = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
    await _messages.close();
  }

  /// Simulate an inbound server frame.
  void deliver(String raw) {
    if (!_messages.isClosed) _messages.add(raw);
  }

  /// Simulate the server hanging up (network drop) without a local [close].
  void simulateServerClose() {
    closed = true;
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}
