import 'dart:math' as math;

/// Pure motion helpers for the speaker grille.
///
/// Bar count, MONITOR convention, and the per-bar tremble formula come from
/// `specs/keryx-face-prototype.html` (9 slots; MONITOR at 0.25 amplitude;
/// `1 + sin(t/90 + i) * 0.5 * amp * rand`). Amplitude mass lives in the
/// widget, which drives [AnimationController.animateTo] with
/// `KeryxTheme.settleDuration` / `KeryxTheme.settleCurve`.
abstract final class GrilleMotion {
  /// Horizontal slots in the prototype grille.
  static const int barCount = 9;

  /// Amplitude the host should inject while MONITOR is open and RX is idle.
  static const double monitorAmplitude = 0.25;

  /// Prototype phase divisor: `performance.now() / 90`.
  static const double phaseMs = 90;

  /// Inclusive idle / full-scale range for injected amplitude.
  static const double minAmplitude = 0;
  static const double maxAmplitude = 1;

  /// Prototype jitter band applied per bar per frame: `0.6 + random() * 0.6`.
  static const double jitterMin = 0.6;
  static const double jitterSpan = 0.6;

  /// Rejects NaN/∞ and clamps into `[0, 1]`.
  static double clampAmplitude(double raw) {
    if (!raw.isFinite) return minAmplitude;
    return raw.clamp(minAmplitude, maxAmplitude);
  }

  /// Prototype scaleY for one slot.
  ///
  /// Rest (amplitude ≤ 0) is exactly `1`. [jitter] is the already-sampled
  /// `0.6 + random * 0.6` term so tests can pin the random source.
  static double scaleY({
    required double amplitude,
    required int barIndex,
    required double elapsedMs,
    required double jitter,
  }) {
    if (amplitude <= minAmplitude) return 1;
    return 1 +
        math.sin(elapsedMs / phaseMs + barIndex) *
            0.5 *
            amplitude *
            jitter;
  }

  /// Samples the prototype jitter band from [random].
  static double sampleJitter(math.Random random) =>
      jitterMin + random.nextDouble() * jitterSpan;
}
