import 'dart:async';

import 'package:keryx/core/floor/transport.dart';
import 'package:keryx/core/protocol/protocol.dart';

/// The LINKED-side counterpart of `MeshFloorTransport`'s composition trick
/// (TASK-032), closing the gap `LinkedController`'s own dartdoc calls out:
/// "separately exposes the concrete `FloorTransport` (`floorTransport`,
/// built once a room is joined) for the host to wire into that same
/// engine — the host-level wiring that makes those two line up is out of
/// this task's scope."
///
/// The problem this solves: [FloorEngine] takes its [FloorTransport] as a
/// required, immutable constructor argument, so it must exist *before* a
/// LiveKit room has been joined. `LinkedController`'s real
/// `LinkedFloorTransport`, on the other hand, cannot exist until AFTER
/// `joinNumbered`/`joinRoomId`/a reconnect completes (it wraps a live
/// `LiveKitRoom`). Neither `FloorEngine` nor `LinkedController` may change
/// to fix this (both live outside this task's `Owned_Paths`), so this class
/// is a synchronously-constructible [FloorTransport] that starts with no
/// delegate (`send` is a no-op, `incoming` is silent) and can be [attach]ed
/// to the real transport once it exists — mirroring how
/// `MeshFloorTransport.attach` swaps in a live `RtcDataChannel` per peer
/// after the fact, just for a single room-wide delegate instead of N
/// per-peer channels.
///
/// KNOWN LIMITATION (disclosed, TASK-035): `LinkedController` does not
/// expose a stream of "the underlying transport changed" — only the current
/// `floorTransport` getter. A live reconnect (`LinkMonitor`'s own internal
/// `_reconnectRoom`) silently swaps `LinkedController`'s private room and
/// transport without any external signal, so this proxy has no way to
/// re-[attach] itself automatically; it keeps forwarding through the
/// pre-reconnect delegate (which the reconnect leaves for outbound `send`s
/// to fail silently against, matching `LinkedFloorTransport.send`'s own
/// "log, never rethrow" contract) until the next explicit
/// [RadioSessionController.retune] rebuilds the whole LINKED chain. Closing
/// this gap for real needs a `floorTransportChanged` stream on
/// `LinkedController` itself — flagged as a follow-up, out of this task's
/// `Owned_Paths` (`lib/services/linked/**`).
class LinkedProxyFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast(sync: true);
  FloorTransport? _delegate;
  StreamSubscription<FloorMessage>? _delegateSub;
  bool _closed = false;

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  /// The delegate this proxy is currently forwarding through, if any.
  FloorTransport? get delegate => _delegate;

  /// Wire [delegate] in as the live transport. Replaces any prior delegate
  /// (a fresh join after [detach], or an explicit re-attach) without
  /// disposing it — ownership of [delegate] stays with whoever built it
  /// (`LinkedController`, via its own `leave()`/`dispose()`), matching
  /// TASK-032's injected-transport ownership convention.
  void attach(FloorTransport delegate) {
    if (_closed) return;
    unawaited(_delegateSub?.cancel());
    _delegate = delegate;
    _delegateSub = delegate.incoming.listen((message) {
      if (!_incoming.isClosed) _incoming.add(message);
    });
  }

  /// Stop forwarding through the current delegate (e.g. before `leave()`).
  /// Does not dispose the delegate itself — see [attach]'s ownership note.
  void detach() {
    unawaited(_delegateSub?.cancel());
    _delegateSub = null;
    _delegate = null;
  }

  @override
  void send(FloorMessage message) {
    if (_closed) return;
    // No delegate yet (join still in flight) or a departed one: drop
    // silently, matching `LinkedFloorTransport.send`'s own "log, never
    // rethrow" contract for a transport in flux — `FloorEngine` never
    // treats a failed `send` as fatal.
    _delegate?.send(message);
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    await _delegateSub?.cancel();
    _delegateSub = null;
    _delegate = null;
    await _incoming.close();
  }
}
