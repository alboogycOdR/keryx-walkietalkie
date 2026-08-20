import 'dart:async';
import 'dart:developer' as developer;

import 'package:keryx/core/floor/transport.dart';
import 'package:keryx/core/protocol/protocol.dart';

import 'rtc_adapter.dart';

/// The concrete [FloorTransport] this task owns: wraps one WebRTC
/// [RtcDataChannel] per peer, encoding/decoding via TASK-006's
/// [FloorCodec]. This is what `FloorEngine` is constructed with in
/// production; `LoopbackHub`/`LoopbackEndpoint` remain the test-only
/// stand-in.
///
/// A [FloorEngine] is per-channel (one roster), so this fans a single
/// logical `send` out to every attached peer's data channel — mirroring
/// [LoopbackHub]'s broadcast semantics for the mesh's N-1 peer connections.
class MeshFloorTransport implements FloorTransport {
  MeshFloorTransport();

  final _incoming = StreamController<FloorMessage>.broadcast(sync: true);
  final Map<String, RtcDataChannel> _channels = <String, RtcDataChannel>{};
  bool _closed = false;

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  /// Attach [channel] as the floor-control transport for [peerId]. Replaces
  /// any prior channel for the same peer (renegotiation).
  void attach(String peerId, RtcDataChannel channel) {
    if (_closed) return;
    _channels[peerId] = channel;
    channel.onMessage = (String text) => _onText(peerId, text);
  }

  void detach(String peerId) {
    _channels.remove(peerId);
  }

  @override
  void send(FloorMessage message) {
    if (_closed) return;
    final wire = FloorCodec.encode(message);
    for (final entry in _channels.entries) {
      if (!entry.value.isOpen) continue;
      try {
        entry.value.send(wire);
      } on Object catch (error, stack) {
        developer.log(
          'mesh floor send to ${entry.key} failed: $error',
          name: 'keryx.mesh',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }

  void _onText(String peerId, String text) {
    final message = FloorCodec.decode(text);
    if (message == null) {
      developer.log(
        'mesh floor: malformed message from $peerId, ignored',
        name: 'keryx.mesh',
      );
      return;
    }
    if (!_incoming.isClosed) _incoming.add(message);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _channels.clear();
    await _incoming.close();
  }
}
