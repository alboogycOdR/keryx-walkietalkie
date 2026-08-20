import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:keryx/core/floor/transport.dart';
import 'package:keryx/core/protocol/protocol.dart';

import 'livekit_adapter.dart';

const _logName = 'keryx.linked';

/// The second concrete [FloorTransport] implementation (TASK-024): wraps
/// LiveKit's room-wide data-message API instead of a per-peer WebRTC
/// `RTCDataChannel`, encoding/decoding via the SAME TASK-006 [FloorCodec]
/// as `MeshFloorTransport` — so `FloorEngine` runs unmodified over either
/// transport (TS §8.4 "floor control messages ride LiveKit data messages,
/// same schema as LOCAL").
///
/// Unlike [MeshFloorTransport] there is no per-peer attach/detach: LiveKit's
/// `publishData` already fans out to every participant in the room, so
/// `send` is a single call rather than an N-way loop.
class LinkedFloorTransport implements FloorTransport {
  LinkedFloorTransport(this._room) {
    _sub = _room.incomingData.listen(
      _onData,
      onError: (Object error, StackTrace stack) {
        developer.log(
          'linked floor: incoming data stream error: $error',
          name: _logName,
          error: error,
          stackTrace: stack,
        );
      },
    );
  }

  final LiveKitRoom _room;
  final _incoming = StreamController<FloorMessage>.broadcast(sync: true);
  late final StreamSubscription<List<int>> _sub;
  bool _closed = false;

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {
    if (_closed) return;
    final wire = FloorCodec.encode(message);
    // Fire-and-forget, matching MeshFloorTransport's synchronous `send`
    // contract — errors are logged, never rethrown to FloorEngine, so one
    // bad send can't break the engine's own control flow.
    unawaited(
      _room.sendData(utf8.encode(wire)).catchError((Object error, StackTrace stack) {
        developer.log(
          'linked floor send failed: $error',
          name: _logName,
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  void _onData(List<int> bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      developer.log('linked floor: non-UTF8 data message, ignored', name: _logName);
      return;
    }
    final message = FloorCodec.decode(text);
    if (message == null) {
      developer.log('linked floor: malformed message, ignored', name: _logName);
      return;
    }
    if (!_incoming.isClosed) _incoming.add(message);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    await _incoming.close();
  }
}
