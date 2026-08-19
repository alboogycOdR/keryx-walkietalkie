import 'dart:math' as math;
import 'dart:typed_data';

/// 3:1 soft-knee compressor with makeup (TS §7.2).
///
/// Envelope is a peak follower. Gain computer uses a quadratic soft knee.
final class SoftKneeCompressor {
  SoftKneeCompressor({
    required this.sampleRateHz,
    this.thresholdDb = -18.0,
    this.ratio = 3.0,
    this.kneeDb = 6.0,
    this.makeupDb = 3.0,
    this.attackMs = 5.0,
    this.releaseMs = 50.0,
  }) {
    if (!(sampleRateHz.isFinite && sampleRateHz > 0)) {
      throw ArgumentError.value(sampleRateHz, 'sampleRateHz');
    }
    if (!(ratio.isFinite && ratio >= 1.0)) {
      throw ArgumentError.value(ratio, 'ratio', 'must be ≥ 1');
    }
    if (!(kneeDb.isFinite && kneeDb >= 0)) {
      throw ArgumentError.value(kneeDb, 'kneeDb');
    }
    _attack = _coeff(attackMs);
    _release = _coeff(releaseMs);
  }

  final double sampleRateHz;
  final double thresholdDb;
  final double ratio;
  double kneeDb;
  double makeupDb;
  final double attackMs;
  final double releaseMs;

  late final double _attack;
  late final double _release;
  double _envelope = 0;

  double processSample(double x) {
    final abs = x.abs();
    if (abs > _envelope) {
      _envelope = _attack * _envelope + (1.0 - _attack) * abs;
    } else {
      _envelope = _release * _envelope + (1.0 - _release) * abs;
    }
    final levelDb = _envelope <= 1e-12 ? -240.0 : 20.0 * math.log(_envelope) / math.ln10;
    return x * _dbToLin(_gainDb(levelDb) + makeupDb);
  }

  void processInPlace(Float32List buffer) {
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = processSample(buffer[i]);
    }
  }

  void reset() {
    _envelope = 0;
  }

  double _gainDb(double levelDb) {
    final halfKnee = kneeDb / 2.0;
    final overshoot = levelDb - thresholdDb;
    if (overshoot <= -halfKnee) {
      return 0;
    }
    final slope = 1.0 - 1.0 / ratio;
    if (overshoot >= halfKnee) {
      return -overshoot * slope;
    }
    final t = overshoot + halfKnee;
    return -(slope * t * t) / (2.0 * kneeDb);
  }

  double _coeff(double ms) {
    if (!(ms.isFinite && ms > 0)) {
      throw ArgumentError.value(ms, 'ms');
    }
    return math.exp(-1.0 / (sampleRateHz * ms / 1000.0));
  }

  static double _dbToLin(double db) => math.pow(10.0, db / 20.0).toDouble();
}
