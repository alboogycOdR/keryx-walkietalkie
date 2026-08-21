import 'dart:async';
import 'dart:math';

import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/protocol/protocol.dart';

/// Simulated lossy/reordering broadcast network for TASK-023's soak
/// harness (KRX-044).
///
/// Every [FloorTransport.send] hop is scheduled independently on the
/// shared [VirtualClock] with random jitter, so two messages sent one
/// after another can be *delivered* out of order at their destination —
/// reordering falls out of independent per-hop delays rather than being
/// modelled as a distinct mechanism. [lossRate] drops a hop entirely
/// before it is ever scheduled. Partitioned peers ([setPartitioned])
/// neither send nor receive, without being detached from the network —
/// membership (the harness's own `roster`) is a separate concern from
/// reachability.
///
/// Read-only consumer of TASK-022's [FloorTransport] contract; this file
/// adds no floor-control logic, only network simulation.
class SimNetwork {
  SimNetwork({
    required this.clock,
    required Random random,
    this.lossRate = 0.0,
    this.minDelay = const Duration(milliseconds: 5),
    this.maxDelay = const Duration(milliseconds: 80),
  }) : _random = random {
    if (lossRate < 0 || lossRate > 1) {
      throw ArgumentError.value(lossRate, 'lossRate', 'must be in [0, 1]');
    }
    if (maxDelay < minDelay) {
      throw ArgumentError.value(maxDelay, 'maxDelay', 'must be >= minDelay');
    }
  }

  final VirtualClock clock;
  final Random _random;
  double lossRate;
  Duration minDelay;
  Duration maxDelay;

  final Map<String, _SimEndpoint> _endpoints = <String, _SimEndpoint>{};
  final Set<String> _partitioned = <String>{};

  /// Currently attached peer IDs.
  Iterable<String> get attached => _endpoints.keys;

  FloorTransport attach(String peerId) {
    if (peerId.isEmpty) {
      throw ArgumentError.value(peerId, 'peerId', 'must not be empty');
    }
    if (_endpoints.containsKey(peerId)) {
      throw StateError('peer $peerId is already attached');
    }
    final endpoint = _SimEndpoint(peerId, this);
    _endpoints[peerId] = endpoint;
    return endpoint;
  }

  void detach(String peerId) {
    _endpoints.remove(peerId)?._close();
    _partitioned.remove(peerId);
  }

  /// While partitioned, [peerId] sends nothing and receives nothing —
  /// simulates a link/relay outage distinct from a hard crash (the peer's
  /// [FloorEngine] keeps running; it just cannot hear or be heard).
  void setPartitioned(String peerId, bool value) {
    if (value) {
      _partitioned.add(peerId);
    } else {
      _partitioned.remove(peerId);
    }
  }

  bool isPartitioned(String peerId) => _partitioned.contains(peerId);

  void _send(String from, FloorMessage message) {
    if (_partitioned.contains(from)) return;
    for (final to in List<String>.of(_endpoints.keys)) {
      if (to == from) continue;
      if (_partitioned.contains(to)) continue;
      if (_random.nextDouble() < lossRate) continue;
      final jitterUs = (maxDelay - minDelay).inMicroseconds;
      final delay = jitterUs <= 0
          ? minDelay
          : minDelay + Duration(microseconds: _random.nextInt(jitterUs + 1));
      clock.schedule(delay, () {
        _endpoints[to]?._deliver(message);
      });
    }
  }
}

class _SimEndpoint implements FloorTransport {
  _SimEndpoint(this.peerId, this._net);

  final String peerId;
  final SimNetwork _net;
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
    _net._send(peerId, message);
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
