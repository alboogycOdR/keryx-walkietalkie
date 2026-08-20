import 'dart:developer' as developer;

import 'package:vibration/vibration.dart';

/// TX haptic compositions (TS §6.4 haptics table).
///
/// Mirrors `KnobHapticFeedback`'s shape exactly (`lib/features/knob/`):
/// `package:vibration` exposes no cross-platform `VibrationEffect.Composition`
/// primitive, so each named composition below is approximated with a
/// duration/amplitude pulse (single tones) or a `pattern:`/`intensities:`
/// sequence (multi-pulse compositions), on amplitude-capable devices, falling
/// back to bare-duration vibration where amplitude control is unavailable.
/// Every method is `try`/`catch`-wrapped and never throws: a haptics failure
/// must never interrupt a live transmission.
abstract final class PttHapticFeedback {
  /// TS §6.4: "PTT grant — PRIMITIVE_QUICK_RISE". Approximated as a single
  /// short, full-amplitude pulse — the closest a bare vibrator motor gets to
  /// a "rising" composition without composition support.
  static const int grantDurationMs = 20;
  static const int grantAmplitude = 255;

  /// TS §6.4: "PTT denied (busy) — PRIMITIVE_THUD ×2". Two short pulses
  /// separated by a brief gap, matching PT's own deny vibration shape
  /// (`navigator.vibrate([18,40,18])` — pulse/pause/pulse, L344).
  static const List<int> deniedPattern = <int>[0, 18, 40, 18];
  static const List<int> deniedIntensities = <int>[0, 255, 0, 255];

  /// TS §6.4: "TOT warning — PRIMITIVE_TICK ×3". Three brief, lighter pulses.
  /// Not fired by `PttButton` itself (TOT is a `FloorEffect.TotWarn()`
  /// concern, owned by the future floor-wiring assembly task) — exposed here
  /// as the shared composition primitive so that task doesn't reinvent it.
  static const List<int> totWarningPattern = <int>[0, 12, 60, 12, 60, 12];
  static const List<int> totWarningIntensities = <int>[0, 153, 0, 153, 0, 153];

  /// Fire the grant composition. Never throws.
  static Future<void> grant() => _fireSingle(
    durationMs: grantDurationMs,
    amplitude: grantAmplitude,
    label: 'grant',
  );

  /// Fire the denied (busy-lockout) composition. Never throws.
  static Future<void> denied() =>
      _firePattern(deniedPattern, deniedIntensities, label: 'denied');

  /// Fire the TOT-warning composition. Never throws. See [totWarningPattern]
  /// dartdoc for why [PttButton] does not call this itself.
  static Future<void> totWarning() => _firePattern(
    totWarningPattern,
    totWarningIntensities,
    label: 'tot',
  );

  static Future<void> _fireSingle({
    required int durationMs,
    required int amplitude,
    required String label,
  }) async {
    try {
      final hasAmplitude = await Vibration.hasAmplitudeControl();
      if (hasAmplitude) {
        await Vibration.vibrate(duration: durationMs, amplitude: amplitude);
      } else {
        await Vibration.vibrate(duration: durationMs);
      }
    } catch (error, stack) {
      developer.log(
        'PTT $label haptic failed: $error',
        name: 'keryx.ptt',
        error: error,
        stackTrace: stack,
      );
    }
  }

  static Future<void> _firePattern(
    List<int> pattern,
    List<int> intensities, {
    required String label,
  }) async {
    try {
      final hasAmplitude = await Vibration.hasAmplitudeControl();
      if (hasAmplitude) {
        await Vibration.vibrate(pattern: pattern, intensities: intensities);
      } else {
        await Vibration.vibrate(pattern: pattern);
      }
    } catch (error, stack) {
      developer.log(
        'PTT $label haptic failed: $error',
        name: 'keryx.ptt',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
