import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/services/platform/platform.dart';

void main() {
  late String manifest;
  late String service;
  late String plugin;
  late String contract;
  late String dartLib;

  setUpAll(() {
    manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    service = File(
      'android/app/src/main/kotlin/za/co/basileia/keryx/RadioForegroundService.kt',
    ).readAsStringSync();
    plugin = File(
      'android/app/src/main/kotlin/za/co/basileia/keryx/RadioServicePlugin.kt',
    ).readAsStringSync();
    contract = File(
      'android/app/src/main/kotlin/za/co/basileia/keryx/RadioServiceContract.kt',
    ).readAsStringSync();
    dartLib = Directory('lib/services/platform')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
  });

  test('manifest declares FGS types mediaPlayback|microphone and required permissions', () {
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    expect(manifest, contains('android.permission.FOREGROUND_SERVICE_MICROPHONE'));
    expect(manifest, contains('android.permission.WAKE_LOCK'));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback|microphone"'));
    expect(manifest, contains('android:name=".RadioForegroundService"'));
    expect(manifest, contains('android:stopWithTask="false"'));
  });

  test('native service uses both FGS types, partial wake lock, transient-may-duck', () {
    expect(service, contains('FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK'));
    expect(service, contains('FOREGROUND_SERVICE_TYPE_MICROPHONE'));
    expect(service, contains('PARTIAL_WAKE_LOCK'));
    expect(service, contains('AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK'));
    expect(service, contains('abandonAudioFocusRequest'));
    expect(service, contains('ACTION_PTT'));
    expect(service, contains('ACTION_STOP'));
    expect(service, contains('SDK_INT >= 34'));
    expect(service, contains('killedDirty'));
    expect(service, contains('EVENT_KILLED'));
  });

  test('Dart and Kotlin wire names are byte-identical', () {
    expect(contract, contains('const val METHOD_CHANNEL = "${RadioServiceConstants.methodChannel}"'));
    expect(contract, contains('const val EVENT_CHANNEL = "${RadioServiceConstants.eventChannel}"'));
    expect(contract, contains('const val PHASE_IDLE = "${RadioServiceConstants.phaseIdle}"'));
    expect(contract, contains('const val PHASE_RX = "${RadioServiceConstants.phaseRx}"'));
    expect(contract, contains('const val PHASE_TX = "${RadioServiceConstants.phaseTx}"'));
    expect(contract, contains('const val EVENT_KILLED = "${RadioServiceConstants.eventServiceKilled}"'));
    expect(contract, contains('const val EVENT_PTT = "${RadioServiceConstants.eventPttAction}"'));
    expect(
      contract,
      contains('const val EVENT_POWER_OFF = "${RadioServiceConstants.eventPowerOffAction}"'),
    );
    expect(
      contract,
      contains('const val RESULT_PTT_ENABLED = "${RadioServiceConstants.resultPttActionEnabled}"'),
    );
  });

  test('service has no polling loops (FR-102)', () {
    expect(service.contains('postDelayed'), isFalse);
    expect(service.contains('scheduleAtFixedRate'), isFalse);
    expect(service.contains('Timer('), isFalse);
    expect(service.contains('while (true)'), isFalse);
    expect(service.contains('Timer.periodic'), isFalse);
  });

  test('Dart facade has no Timer.periodic / polling', () {
    expect(dartLib.contains('Timer.periodic'), isFalse);
    expect(dartLib.contains('Timer('), isFalse);
    expect(dartLib.contains('Stopwatch('), isFalse);
    expect(dartLib.contains('Future.delayed'), isFalse);
  });

  test('PTT action is gated to Android 14+ in native', () {
    expect(plugin, contains('pttActionPermitted'));
    expect(service, contains('fun pttActionPermitted(): Boolean = Build.VERSION.SDK_INT >= 34'));
    expect(service, contains('if (pttActionPermitted())'));
  });

  test('plugin start watchdog is the only delayed callback and is bounded', () {
    expect(plugin, contains('START_TIMEOUT_MS = 5000L'));
    expect(plugin, contains('postDelayed'));
    expect(plugin, contains('removeCallbacks'));
  });
}
