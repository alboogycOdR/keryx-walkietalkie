import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/services/session/session.dart'
    show RadioSessionController, StationInfo;

/// The narrow surface [FaceScreen] actually drives on a radio session.
///
/// TASK-035's `RadioSessionController` (`lib/services/session/**`, out of
/// this task's `Owned_Paths`) performs real I/O in `start()` — real UDP
/// sockets via `IoSignalingEndpoint`/`NsdDiscoveryService.production` for
/// the LOCAL chain — which cannot run inside `flutter test` (no real
/// network/platform channels there). `RadioSessionController` was not
/// designed with a mockable interface (it is a plain concrete class with no
/// `implements` contract), and this task cannot add one to it without
/// touching `lib/services/session/**`.
///
/// So the seam lives here instead: [SessionHost] is the exact shape
/// `FaceScreen` calls (`start`, `retune`, `joinEvent`, `dispose`,
/// `floorEngine`, `stations`), and [RadioSessionHostAdapter] is a
/// near-pass-through wrapper around a real `RadioSessionController`.
/// Production's default `FaceScreen.sessionFactory` builds a real
/// controller and wraps it in this adapter; widget tests instead hand
/// `FaceScreen` a small hand-written class implementing [SessionHost]
/// directly, with no real I/O anywhere in the test.
abstract class SessionHost {
  /// The engine driving the active LOCAL/LINKED chain. Throws
  /// [StateError] until [start] has completed — mirrors
  /// `RadioSessionController.floorEngine`'s own contract exactly, so
  /// callers write one guard, not two.
  FloorEngine get floorEngine;

  /// Remote stations on the tuned channel. See
  /// `lib/services/session/station_info.dart`'s dartdoc for why every
  /// entry currently carries a placeholder `signalQuality` until KRX-035's
  /// telemetry feed exists.
  Stream<List<StationInfo>> get stations;

  Future<void> start();

  /// Full teardown/rebuild for a channel change — see
  /// `RadioSessionController.retune`'s own dartdoc for why nothing
  /// channel-scoped survives it.
  Future<void> retune({required int channel, required int code});

  /// Join a scanned/tapped Event QR payload (FR-043/FR-044). Requires an
  /// already-active LINKED chain, per `RadioSessionController.joinEvent`'s
  /// own contract.
  Future<void> joinEvent(EventLinkPayload payload);

  Future<void> dispose();
}

/// Thin pass-through [SessionHost] over a real [RadioSessionController].
/// Every method forwards 1:1 — this class exists purely to satisfy Dart's
/// nominal-typing requirement (`implements` must be explicit), not to add
/// behaviour of its own.
class RadioSessionHostAdapter implements SessionHost {
  RadioSessionHostAdapter(this._controller);

  final RadioSessionController _controller;

  /// Debug/test seam mirroring `RadioSessionController`'s own — lets a
  /// production-path integration test reach into the composed chain
  /// without widening [SessionHost] itself.
  RadioSessionController get debugController => _controller;

  @override
  FloorEngine get floorEngine => _controller.floorEngine;

  @override
  Stream<List<StationInfo>> get stations => _controller.stations;

  @override
  Future<void> start() => _controller.start();

  @override
  Future<void> retune({required int channel, required int code}) =>
      _controller.retune(channel: channel, code: code);

  @override
  Future<void> joinEvent(EventLinkPayload payload) =>
      _controller.joinEvent(payload);

  @override
  Future<void> dispose() => _controller.dispose();
}
