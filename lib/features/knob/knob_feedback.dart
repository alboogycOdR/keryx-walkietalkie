import 'dart:developer' as developer;

import 'package:vibration/vibration.dart';

/// Per-detent haptic feedback for the tuning knob.
///
/// TS §6.4: knob detent haptic = "PRIMITIVE_CLICK (scale 0.6)". There is no
/// cross-platform `VibrationEffect.Composition` primitive exposed by
/// `package:vibration`, so this approximates PRIMITIVE_CLICK as the
/// shortest practical pulse (8 ms — TS §6.2's own "8 ms mechanical tick
/// sample" duration) at 0.6 of full amplitude on amplitude-capable devices,
/// falling back to a bare duration pulse where amplitude control is
/// unavailable.
///
/// [KeryxTuningKnob] fires [click] synchronously from the same callback
/// that invokes its `onDetent` hook, so the haptic and the caller's
/// tick-sound/LCD-update hooks are *initiated* in the same frame per TS
/// §6.2 ("all in the same frame") — completion of the (inherently
/// asynchronous) platform vibration call happens later, same as any other
/// platform channel call.
abstract final class KnobHapticFeedback {
  /// TS §6.2: "8 ms mechanical tick sample" — reused as PRIMITIVE_CLICK's
  /// pulse duration since no shorter normative number exists.
  static const int clickDurationMs = 8;

  /// TS §6.4 "PRIMITIVE_CLICK (scale 0.6)". Amplitude is 1-255 on Android.
  static const int clickAmplitude = 153; // (255 * 0.6).round()

  /// Fire one detent click. Never throws: any platform/plugin failure
  /// (including "no vibrator", "plugin not registered" in tests, or a
  /// missing platform implementation) is logged and swallowed so a haptics
  /// glitch can never interrupt tuning.
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
        'Knob detent haptic failed: $error',
        name: 'keryx.knob',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
