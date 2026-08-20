import 'dart:async';

import 'package:keryx/core/state/radio_state.dart';

/// Drives [KeryxSpeakerGrille.amplitude] from [RadioState] until a real
/// audio-engine RMS tap is wired in.
///
/// `lib/core/audio/**` (`bed_mixer`/`rx_processor`) already computes the
/// real signal levels that should feed this, but wiring the grille to a
/// live PCM tap is an audio-engine integration, not a face-layout one — the
/// same "engineering-approved, spec-silent" split TASK-016's own review
/// approved for its `amplitude` parameter (neither spec constrains the
/// amplitude source). This class supplies a state-driven placeholder so the
/// grille visibly reacts to TX/RX/MONITOR instead of sitting inert, and is
/// the single seam a future audio-wiring task swaps out — nothing else in
/// `lib/features/face/**` depends on how the stream is produced.
class FaceAmplitudeSource {
  FaceAmplitudeSource() {
    _timer = Timer.periodic(const Duration(milliseconds: 90), (_) => _tick());
  }

  static const double _idleAmplitude = 0;
  static const double _activeAmplitude = 0.65;

  final StreamController<double> _controller = StreamController<double>.broadcast();
  late final Timer _timer;
  double _target = _idleAmplitude;
  double _current = _idleAmplitude;

  Stream<double> get stream => _controller.stream;

  /// Called on every rebuild with the latest reducer state. Cheap and
  /// idempotent — just updates the target the periodic tick eases toward.
  void update(RadioState state) {
    final active =
        state.phase == RadioPhase.tx ||
        state.phase == RadioPhase.rxActive ||
        state.isMonitorOpen;
    _target = active ? _activeAmplitude : _idleAmplitude;
  }

  void _tick() {
    _current += (_target - _current) * 0.35;
    if (!_controller.isClosed) _controller.add(_current);
  }

  void dispose() {
    _timer.cancel();
    unawaited(_controller.close());
  }
}
