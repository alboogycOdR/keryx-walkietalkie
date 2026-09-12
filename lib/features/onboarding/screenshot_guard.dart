import 'package:flutter/services.dart';

/// Turns Android `FLAG_SECURE` on or off so the recovery-phrase screen
/// cannot be screenshotted (Design §2.6, V2-VT-002, V2-FR-002).
///
/// Native handling lives on the `za.co.basileia.keryx/screenshot_guard`
/// MethodChannel. `android/**` is outside this task's territory, so the
/// Dart client swallows [MissingPluginException] — tests inject a fake
/// and assert the call; the shell/native owner wires the window flag.
abstract interface class ScreenshotGuard {
  Future<void> setSecure(bool secure);
}

/// Production guard. No-ops when the native handler is not registered
/// (widget tests, desktop, or before the Android plugin lands).
class MethodChannelScreenshotGuard implements ScreenshotGuard {
  MethodChannelScreenshotGuard([MethodChannel? channel])
    : _channel =
          channel ??
          const MethodChannel('za.co.basileia.keryx/screenshot_guard');

  static const String methodSetSecure = 'setSecure';

  final MethodChannel _channel;

  @override
  Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>(methodSetSecure, <String, Object?>{
        'secure': secure,
      });
    } on MissingPluginException {
      // Native plugin is out of this territory. Fail open in tests.
    } on PlatformException {
      // Same: a missing or failing native call must not block onboarding.
    }
  }
}

/// Test / golden stand-in.
class NoopScreenshotGuard implements ScreenshotGuard {
  const NoopScreenshotGuard();

  @override
  Future<void> setSecure(bool secure) async {}
}

/// Records `setSecure` invocations for tests.
class RecordingScreenshotGuard implements ScreenshotGuard {
  final List<bool> calls = <bool>[];

  @override
  Future<void> setSecure(bool secure) async {
    calls.add(secure);
  }
}
