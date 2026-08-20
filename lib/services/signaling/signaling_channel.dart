/// Bidirectional text channel. Production wraps a WebSocket; tests use
/// in-process pipes. One channel = one remote peer after handshake.
abstract class SignalingChannel {
  /// Dial target or inbound remote address, for logs. Not a peerId.
  String get remoteLabel;

  Stream<String> get incoming;

  void send(String text);

  Future<void> close();
}

/// Bind + accept + dial. Production is loopback-free LAN HTTP/WebSocket;
/// tests use [InProcessSignalingHub].
abstract class SignalingEndpoint {
  /// Bound TCP / virtual port after [bind]. `0` before bind.
  int get port;

  Stream<SignalingChannel> get incoming;

  Future<void> bind();

  /// Dial [host]:[port] from a [DiscoveredPeer] — never invent an address.
  Future<SignalingChannel> connect(String host, int port);

  Future<void> close();
}
