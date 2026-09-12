import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/services/session/session.dart'
    show RadioSessionController, StationInfo;

/// The narrow surface the persistent [RadioHost] drives on a radio session.
///
/// Hoisted out of `lib/features/face/session_host.dart` (deleted by TASK-094)
/// so the host can keep the test seam after the legacy face is gone.
/// v2 joins go through [RadioSessionController.switchTarget].
abstract class SessionHost {
  FloorEngine get floorEngine;

  Stream<List<StationInfo>> get stations;

  Future<void> start();

  Future<void> dispose();
}

/// Thin pass-through [SessionHost] over a real [RadioSessionController].
class RadioSessionHostAdapter implements SessionHost {
  RadioSessionHostAdapter(this._controller);

  final RadioSessionController _controller;

  RadioSessionController get debugController => _controller;

  @override
  FloorEngine get floorEngine => _controller.floorEngine;

  @override
  Stream<List<StationInfo>> get stations => _controller.stations;

  @override
  Future<void> start() => _controller.start();

  @override
  Future<void> dispose() => _controller.dispose();
}
