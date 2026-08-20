import 'dart:async';

import 'package:keryx/core/floor/transport.dart';
import 'package:keryx/core/protocol/protocol.dart';

/// A single-device [FloorTransport] with no wire.
///
/// TASK-022's `FloorEngine` needs a transport to construct, and TASK-020
/// (`lib/services/signaling/**`, the LAN transport that would actually carry
/// `FloorMessage`s to peers) is still `TBD`. Until TASK-020 lands, the face
/// runs [FloorEngine] with only the local peer in its roster: nothing is ever
/// sent (there is no one to send to) and nothing ever arrives, but the engine
/// still self-arbitrates every local PTT request (single-element roster ⇒
/// local device is always the elected arbiter, see `Arbiter.elect`), so a
/// standalone install grants its own transmissions immediately instead of
/// hanging on a network that does not exist yet — the "LOCAL-less simulated
/// grant" the task dossier calls for.
///
/// This is intentionally the ONLY implementation of [FloorTransport] this
/// task ships. Swapping it for a real LAN/LiveKit transport is TASK-020's
/// job and does not touch `lib/features/face/**` beyond the single
/// constructor call in [FaceScreen] that builds the [FloorEngine].
class LocalFloorTransport implements FloorTransport {
  final StreamController<FloorMessage> _incoming =
      StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {
    // No peers to deliver to yet — see class dartdoc.
  }

  void dispose() {
    unawaited(_incoming.close());
  }
}
