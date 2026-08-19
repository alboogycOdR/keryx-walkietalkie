import 'dart:math';
import 'dart:typed_data';

import 'biquad.dart';

/// Optional voice-bus hiss, coloured like the PT bed (1800 Hz / Q 0.7).
///
/// Mix level is supplied by the caller (squelch-knob mapped). Deterministic
/// when constructed with a fixed [seed].
final class HissFloor {
  HissFloor({
    required this.sampleRateHz,
    int seed = 0x4B455258,
    double centerHz = 1800,
    double q = 0.7,
  })  : _rng = Random(seed),
        _colour = Biquad.bandPass(
          sampleRateHz: sampleRateHz,
          centerHz: centerHz,
          q: q,
        );

  final double sampleRateHz;
  final Random _rng;
  final Biquad _colour;

  void mixInto(Float32List buffer, double level) {
    if (!(level.isFinite && level >= 0)) {
      throw ArgumentError.value(level, 'level', 'must be a finite ≥ 0');
    }
    if (level == 0) {
      return;
    }
    for (var i = 0; i < buffer.length; i++) {
      final noise = _rng.nextDouble() * 2.0 - 1.0;
      buffer[i] += _colour.processSample(noise) * level;
    }
  }

  void reset() {
    _colour.reset();
  }
}
