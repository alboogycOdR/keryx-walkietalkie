import 'dart:async';

import 'package:keryx/core/protocol/protocol.dart';

/// Broadcast transport for §8.6 messages. LOCAL data channels and
/// LiveKit data messages both adapt to this; tests use [LoopbackHub].
abstract class FloorTransport {
  void send(FloorMessage message);

  Stream<FloorMessage> get incoming;
}

/// In-process fan-out used by unit tests and by TASK-023's soak harness.
///
/// Delivery is synchronous (`sync: true`) so a send is observed by every
/// other attached engine before [send] returns. Optional [drop] simulates
/// loss without a wall clock.
class LoopbackHub {
  final Map<String, LoopbackEndpoint> _endpoints = <String, LoopbackEndpoint>{};
  final List<_Pending> _pending = <_Pending>[];
  int _flushDepth = 0;

  /// Return `true` to drop [message] on the [from] → [to] hop.
  bool Function(String from, String to, FloorMessage message)? drop;

  /// Currently attached peer IDs.
  Iterable<String> get attached => _endpoints.keys;

  /// Deliver [message] to [to] without a sender hop. Test / soak helper.
  void inject(String to, FloorMessage message) {
    _pending.add(_Pending(to, message));
    _flush();
  }

  LoopbackEndpoint attach(String peerId) {
    if (peerId.isEmpty) {
      throw ArgumentError.value(peerId, 'peerId', 'must not be empty');
    }
    if (_endpoints.containsKey(peerId)) {
      throw StateError('peer $peerId is already attached');
    }
    final endpoint = LoopbackEndpoint._(peerId, this);
    _endpoints[peerId] = endpoint;
    return endpoint;
  }

  void detach(String peerId) {
    final endpoint = _endpoints.remove(peerId);
    endpoint?._close();
  }

  void _broadcast(String from, FloorMessage message) {
    for (final endpoint in List<LoopbackEndpoint>.of(_endpoints.values)) {
      if (endpoint.peerId == from) continue;
      final shouldDrop = drop?.call(from, endpoint.peerId, message) ?? false;
      if (shouldDrop) continue;
      _pending.add(_Pending(endpoint.peerId, message));
    }
    _flush();
  }

  /// Drain the delivery queue without re-entering a subscriber. Nested
  /// [send]s enqueue and run after the current handler returns, so a
  /// grant that immediately produces TX_START cannot hit a sync
  /// broadcast controller mid-callback.
  void _flush() {
    if (_flushDepth > 0) return;
    _flushDepth++;
    try {
      while (_pending.isNotEmpty) {
        final next = _pending.removeAt(0);
        _endpoints[next.to]?._deliver(next.message);
      }
    } finally {
      _flushDepth--;
    }
  }
}

class _Pending {
  const _Pending(this.to, this.message);

  final String to;
  final FloorMessage message;
}

class LoopbackEndpoint implements FloorTransport {
  LoopbackEndpoint._(this.peerId, this._hub);

  final String peerId;
  final LoopbackHub _hub;
  final StreamController<FloorMessage> _incoming =
      StreamController<FloorMessage>.broadcast(sync: true);
  bool _closed = false;

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {
    if (_closed) {
      throw StateError('endpoint $peerId is detached');
    }
    _hub._broadcast(peerId, message);
  }

  void _deliver(FloorMessage message) {
    if (!_closed && !_incoming.isClosed) {
      _incoming.add(message);
    }
  }

  void _close() {
    _closed = true;
    if (!_incoming.isClosed) {
      _incoming.close();
    }
  }
}
