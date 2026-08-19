import 'dart:math' as math;
import 'dart:typed_data';

/// Transposed-direct-form-II biquad. Coefficients are already a0-normalised.
final class Biquad {
  Biquad({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double _z1 = 0;
  double _z2 = 0;

  /// RBJ cookbook high-pass.
  factory Biquad.highPass({
    required double sampleRateHz,
    required double cutoffHz,
    double q = 0.7071067811865476,
  }) {
    final w0 = _omega(sampleRateHz, cutoffHz);
    final cosw = math.cos(w0);
    final alpha = math.sin(w0) / (2.0 * q);
    final a0 = 1.0 + alpha;
    return Biquad(
      b0: ((1.0 + cosw) / 2.0) / a0,
      b1: (-(1.0 + cosw)) / a0,
      b2: ((1.0 + cosw) / 2.0) / a0,
      a1: (-2.0 * cosw) / a0,
      a2: (1.0 - alpha) / a0,
    );
  }

  /// RBJ cookbook low-pass.
  factory Biquad.lowPass({
    required double sampleRateHz,
    required double cutoffHz,
    double q = 0.7071067811865476,
  }) {
    final w0 = _omega(sampleRateHz, cutoffHz);
    final cosw = math.cos(w0);
    final alpha = math.sin(w0) / (2.0 * q);
    final a0 = 1.0 + alpha;
    return Biquad(
      b0: ((1.0 - cosw) / 2.0) / a0,
      b1: (1.0 - cosw) / a0,
      b2: ((1.0 - cosw) / 2.0) / a0,
      a1: (-2.0 * cosw) / a0,
      a2: (1.0 - alpha) / a0,
    );
  }

  /// Constant-skirt band-pass (0 dB peak). Used for the hiss floor colour.
  factory Biquad.bandPass({
    required double sampleRateHz,
    required double centerHz,
    double q = 0.7,
  }) {
    final w0 = _omega(sampleRateHz, centerHz);
    final alpha = math.sin(w0) / (2.0 * q);
    final a0 = 1.0 + alpha;
    return Biquad(
      b0: alpha / a0,
      b1: 0,
      b2: -alpha / a0,
      a1: (-2.0 * math.cos(w0)) / a0,
      a2: (1.0 - alpha) / a0,
    );
  }

  double processSample(double x) {
    final y = b0 * x + _z1;
    _z1 = b1 * x - a1 * y + _z2;
    _z2 = b2 * x - a2 * y;
    return y;
  }

  void processInPlace(Float32List buffer) {
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = processSample(buffer[i]);
    }
  }

  void reset() {
    _z1 = 0;
    _z2 = 0;
  }

  static double _omega(double sampleRateHz, double hz) {
    if (!(sampleRateHz.isFinite && sampleRateHz > 0)) {
      throw ArgumentError.value(sampleRateHz, 'sampleRateHz');
    }
    if (!(hz.isFinite && hz > 0 && hz < sampleRateHz / 2)) {
      throw ArgumentError.value(hz, 'hz', 'must be in (0, Nyquist)');
    }
    return 2.0 * math.pi * hz / sampleRateHz;
  }
}
