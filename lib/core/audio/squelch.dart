import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

/// TASK-008 persists squelch as an integer detent 0–10. This type is the
/// audio-side contract: 0 = closed / silent, 10 = open / faint bed (FR-061).
///
/// Storage stays in `lib/core/settings` (out of territory). Hosts pass the
/// detent in; we never import that package.
abstract final class Squelch {
  static const int minDetent = 0;
  static const int maxDetent = 10;

  /// FR-061: the open end is a *faint* bed, not full [static_bed_3].
  /// Matches the prototype's monitor hiss (`setHiss(.12)`).
  static const double maxRestingBed = 0.12;

  /// Closed-gate threshold (detent 0), dBFS.
  static const double closedGateDb = -12.0;

  /// Open-gate threshold (detent 10), dBFS.
  static const double openGateDb = -40.0;

  static void checkDetent(int detent) {
    if (detent < minDetent || detent > maxDetent) {
      throw ArgumentError.value(
        detent,
        'detent',
        'squelch detent must be $minDetent–$maxDetent',
      );
    }
  }

  /// Resting SFX-bed level in 0..[maxRestingBed]. Monotonic in [detent].
  static double bedLevelFromDetent(int detent) {
    checkDetent(detent);
    return (detent / maxDetent) * maxRestingBed;
  }

  /// RX gate open threshold as linear amplitude. Monotonic *decreasing*
  /// in [detent]: higher detent = more open = weaker signals pass.
  static double gateThresholdFromDetent(int detent) {
    checkDetent(detent);
    final t = detent / maxDetent;
    final db = closedGateDb + t * (openGateDb - closedGateDb);
    return math.pow(10.0, db / 20.0).toDouble();
  }
}

/// Energy gate on the voice bus. Closed → silence; open → passthrough.
///
/// Hysteresis is 6 dB below the open threshold so the gate does not chatter
/// around a single RMS estimate. State is sticky across blocks.
final class RxGate {
  RxGate({double? threshold}) : _threshold = threshold ?? Squelch.gateThresholdFromDetent(5);

  static const double hysteresisRatio = 0.5;

  double _threshold;
  bool _open = false;

  double get threshold => _threshold;

  set threshold(double value) {
    if (!(value.isFinite && value >= 0)) {
      throw ArgumentError.value(value, 'threshold', 'must be a finite ≥ 0');
    }
    _threshold = value;
  }

  bool get isOpen => _open;

  /// Writes [input] or silence into [output]. Buffers must be the same length.
  void process(Float32List input, Float32List output) {
    if (output.length != input.length) {
      throw ArgumentError.value(
        output.length,
        'output.length',
        'must match input (${input.length})',
      );
    }
    final rms = rmsOf(input);
    final wasOpen = _open;
    if (!_open && rms >= _threshold) {
      _open = true;
    } else if (_open && rms < _threshold * hysteresisRatio) {
      _open = false;
    }
    if (_open != wasOpen) {
      developer.log(
        'RX gate ${_open ? 'open' : 'closed'} rms=$rms thr=$_threshold',
        name: 'keryx.audio.dsp',
      );
    }
    if (_open) {
      if (!identical(input, output)) {
        output.setRange(0, output.length, input);
      }
    } else {
      output.fillRange(0, output.length, 0);
    }
  }

  void reset() {
    _open = false;
  }

  static double rmsOf(Float32List input) {
    if (input.isEmpty) {
      return 0;
    }
    var acc = 0.0;
    for (final s in input) {
      if (!s.isFinite) {
        throw ArgumentError.value(s, 'input', 'must be finite');
      }
      acc += s * s;
    }
    return math.sqrt(acc / input.length);
  }
}
