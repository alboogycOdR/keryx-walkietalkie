import 'package:flutter/services.dart';

/// Raises screen brightness to maximum while My code is shown
/// (Design §2.4).
///
/// Native handling lives on `za.co.basileia.keryx/screen_brightness`.
/// `android/**` is outside this territory; missing plugins no-op.
abstract interface class ScreenBrightnessController {
  Future<void> setMaximum();
  Future<void> restore();
}

class MethodChannelScreenBrightness implements ScreenBrightnessController {
  MethodChannelScreenBrightness([MethodChannel? channel])
    : _channel =
          channel ??
          const MethodChannel('za.co.basileia.keryx/screen_brightness');

  static const String methodSetMaximum = 'setMaximum';
  static const String methodRestore = 'restore';

  final MethodChannel _channel;

  @override
  Future<void> setMaximum() async {
    try {
      await _channel.invokeMethod<void>(methodSetMaximum);
    } on MissingPluginException {
      // Native plugin is out of this territory.
    } on PlatformException {
      // Fail open — the QR is still usable at ambient brightness.
    }
  }

  @override
  Future<void> restore() async {
    try {
      await _channel.invokeMethod<void>(methodRestore);
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }
}

class NoopScreenBrightness implements ScreenBrightnessController {
  const NoopScreenBrightness();

  @override
  Future<void> setMaximum() async {}

  @override
  Future<void> restore() async {}
}

class RecordingScreenBrightness implements ScreenBrightnessController {
  int setMaximumCount = 0;
  int restoreCount = 0;

  @override
  Future<void> setMaximum() async {
    setMaximumCount++;
  }

  @override
  Future<void> restore() async {
    restoreCount++;
  }
}
