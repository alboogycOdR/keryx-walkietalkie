import 'dart:async';

import 'signaling_channel.dart';

/// In-process WebSocket stand-in. Unit tests pair devices through this
/// hub instead of binding real sockets (task: "in-process pairs, not
/// real sockets").
class InProcessSignalingHub {
  final Map<int, InProcessSignalingEndpoint> _listeners =
      <int, InProcessSignalingEndpoint>{};
  int _nextPort = 40000;

  InProcessSignalingEndpoint endpoint() => InProcessSignalingEndpoint._(this);

  void _register(InProcessSignalingEndpoint endpoint) {
    final port = _nextPort++;
    endpoint._port = port;
    _listeners[port] = endpoint;
  }

  void _unregister(InProcessSignalingEndpoint endpoint) {
    _listeners.remove(endpoint.port);
  }

  SignalingChannel connectTo(int port, {String host = '10.0.0.2'}) {
    final target = _listeners[port];
    if (target == null || target._closed) {
      throw StateError('no signaling listener on port $port');
    }
    final aToB = StreamController<String>();
    final bToA = StreamController<String>();
    var closed = false;
    Future<void> closeBoth() async {
      if (closed) return;
      closed = true;
      await aToB.close();
      await bToA.close();
    }

    final client = _PipeChannel(
      remoteLabel: '$host:$port',
      incoming: bToA,
      outgoing: aToB,
      closeBoth: closeBoth,
    );
    final server = _PipeChannel(
      remoteLabel: 'in-process',
      incoming: aToB,
      outgoing: bToA,
      closeBoth: closeBoth,
    );
    // Buffer on the server pipe until SignalingService listens; deliver
    // the accept asynchronously so the dialer can attach first.
    scheduleMicrotask(() {
      if (!target._closed) target._accept(server);
    });
    return client;
  }
}

class InProcessSignalingEndpoint implements SignalingEndpoint {
  InProcessSignalingEndpoint._(this._hub);

  final InProcessSignalingHub _hub;
  final _incoming = StreamController<SignalingChannel>.broadcast();
  int _port = 0;
  bool _closed = false;
  bool _bound = false;

  @override
  int get port => _port;

  @override
  Stream<SignalingChannel> get incoming => _incoming.stream;

  @override
  Future<void> bind() async {
    if (_closed) throw StateError('endpoint is closed');
    if (_bound) return;
    _hub._register(this);
    _bound = true;
  }

  @override
  Future<SignalingChannel> connect(String host, int port) async {
    if (_closed || !_bound) {
      throw StateError('endpoint is not bound');
    }
    if (host.isEmpty) {
      throw ArgumentError.value(host, 'host', 'must be non-empty');
    }
    return _hub.connectTo(port, host: host);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _hub._unregister(this);
    await _incoming.close();
  }

  void _accept(SignalingChannel channel) {
    if (_closed || _incoming.isClosed) {
      channel.close();
      return;
    }
    _incoming.add(channel);
  }
}

class _PipeChannel implements SignalingChannel {
  _PipeChannel({
    required this.remoteLabel,
    required StreamController<String> incoming,
    required StreamController<String> outgoing,
    required Future<void> Function() closeBoth,
  }) : _incoming = incoming,
       _outgoing = outgoing,
       _closeBoth = closeBoth;

  @override
  final String remoteLabel;

  final StreamController<String> _incoming;
  final StreamController<String> _outgoing;
  final Future<void> Function() _closeBoth;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  void send(String text) {
    if (_outgoing.isClosed) return;
    _outgoing.add(text);
  }

  @override
  Future<void> close() => _closeBoth();
}
