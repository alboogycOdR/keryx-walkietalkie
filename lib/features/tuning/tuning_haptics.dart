import 'dart:developer' as developer;

import 'package:vibration/vibration.dart';

/// Per-step haptic feedback for the CH▲/CH▼ steppers and keypad.
///
/// Mirrors `KnobHapticFeedback`'s shape exactly (`lib/features/knob/`,
/// per that file's own dartdoc): `package:vibration` exposes no
/// cross-platform `VibrationEffect.Composition` primitive, so
/// PRIMITIVE_CLICK is approximated as the shortest practical pulse at 0.6 of
/// full amplitude, falling back to a bare duration pulse where amplitude
/// control is unavailable. Never throws — a haptics glitch must never
/// interrupt tuning, and FR-106 requires the whole tuning path to remain
/// operable "haptic-and-sound-only" with the screen off, so this feedback is
/// load-bearing, not decorative.
abstract final class TuningHapticFeedback {
  /// Reused from TS §6.2's "8 ms mechanical tick sample" (same reasoning as
  /// `KnobHapticFeedback.clickDurationMs`) — the steppers and the knob emit
  /// the same PRIMITIVE_CLICK per TS §6.4, so they should feel identical.
  static const int clickDurationMs = 8;

  /// TS §6.4 "PRIMITIVE_CLICK (scale 0.6)".
  static const int clickAmplitude = 153; // (255 * 0.6).round()

  /// Fire one step click. Never throws.
  static Future<void> click() async {
    try {
      final hasAmplitude = await Vibration.hasAmplitudeControl();
      if (hasAmplitude) {
        await Vibration.vibrate(
          duration: clickDurationMs,
          amplitude: clickAmplitude,
        );
      } else {
        await Vibration.vibrate(duration: clickDurationMs);
      }
    } catch (error, stack) {
      developer.log(
        'Tuning step haptic failed: $error',
        name: 'keryx.tuning',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
