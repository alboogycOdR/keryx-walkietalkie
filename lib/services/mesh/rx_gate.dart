import 'dart:async';

import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/state/radio_state.dart';

/// Polls an RX amplitude sample for [peerId]. Production wires this to
/// `RTCRtpReceiver.getStats()` (`audioLevel`, RFC/WebRTC stats spec) per
/// connection; on-device calibration is the later bench task the
/// Description defers — this interface is the seam that leaves for it.
typedef LevelSource = Future<double> Function(String peerId);

/// Gates RX rendering by TX_START/TX_END (TS §8.3 step 3: mesh delivers
/// audio from every peer connection, but only the current floor holder's
/// track is ever actually live on the sender side — this is the receiver's
/// half of that contract, and the seam that feeds the grille's amplitude
/// tap). Consumes [FloorEngine.effects]; never touches [RadioState] itself.
class RxGate {
  RxGate({
    required FloorEngine floorEngine,
    LevelSource? levelSource,
    Duration pollInterval = const Duration(milliseconds: 60),
  }) : _floorEngine = floorEngine,
       _levelSource = levelSource,
       _pollInterval = pollInterval {
    _sub = floorEngine.effects.listen(_onEffect);
  }

  final FloorEngine _floorEngine;
  final LevelSource? _levelSource;
  final Duration _pollInterval;

  StreamSubscription<FloorEffect>? _sub;
  Timer? _poll;
  bool _disposed = false;

  final _holderController = StreamController<String?>.broadcast();
  final _levelController = StreamController<double>.broadcast();

  /// The peerId currently gated open for RX, or `null` when the floor is
  /// idle. `null` on emission means "mute everything" — there is no live
  /// speaker to render.
  Stream<String?> get holderChanges => _holderController.stream;

  /// Amplitude samples for the currently gated peer, `[0.0, 1.0]`. Empty
  /// while no peer holds the floor (see [holderChanges]).
  Stream<double> get levels => _levelController.stream;

  String? get currentHolder => _floorEngine.holder;

  void _onEffect(FloorEffect effect) {
    if (_disposed) return;
    if (effect is! DispatchRadio) return;
    final event = effect.event;
    if (event is RemoteFloorStarted) {
      _open(_floorEngine.holder);
    } else if (event is RemoteFloorEnded) {
      _close();
    }
  }

  void _open(String? peerId) {
    _stopPolling();
    if (!_holderController.isClosed) _holderController.add(peerId);
    if (peerId == null || _levelSource == null) return;
    _poll = Timer.periodic(_pollInterval, (_) async {
      final level = await _levelSource(peerId);
      if (!_disposed && !_levelController.isClosed) {
        _levelController.add(level.clamp(0.0, 1.0));
      }
    });
  }

  void _close() {
    _stopPolling();
    if (!_holderController.isClosed) _holderController.add(null);
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopPolling();
    await _sub?.cancel();
    await _holderController.close();
    await _levelController.close();
  }
}
