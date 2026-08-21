import 'dart:async';

import 'package:flutter/services.dart';

import 'radio_service_constants.dart';
import 'radio_service_events.dart';
import 'radio_transport_phase.dart';

class RadioServiceStartInfo {
  const RadioServiceStartInfo({required this.pttActionEnabled});

  /// Native includes the PTT notification action on Android 14+ only.
  final bool pttActionEnabled;
}

/// Native FGS + notification + wake-lock + audio-focus. Production is a
/// Method/Event channel; tests inject [FakeRadioServicePlatform].
abstract class RadioServicePlatform {
  Future<RadioServiceStartInfo> start({
    required String channelLabel,
    String? subtitle,
  });
  Future<void> stop();
  Future<void> setPhase(RadioTransportPhase phase);
  Future<void> updateNotification({
    required String channelLabel,
    String? subtitle,
  });
  Stream<RadioServiceEvent> get events;
}

class ChannelRadioServicePlatform implements RadioServicePlatform {
  ChannelRadioServicePlatform({MethodChannel? methods, EventChannel? events})
    : _methods =
          methods ?? const MethodChannel(RadioServiceConstants.methodChannel),
      _events = events ?? const EventChannel(RadioServiceConstants.eventChannel);

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<RadioServiceEvent>? _parsed;

  @override
  Stream<RadioServiceEvent> get events {
    return _parsed ??= _events.receiveBroadcastStream().map((raw) {
      if (raw is! Map) {
        return const RadioServiceFailed('malformed radio service event');
      }
      return radioServiceEventFromMap(raw) ??
          const RadioServiceFailed('unknown radio service event');
    });
  }

  @override
  Future<RadioServiceStartInfo> start({
    required String channelLabel,
    String? subtitle,
  }) async {
    final raw = await _methods.invokeMapMethod<String, Object?>(
      RadioServiceConstants.methodStart,
      <String, Object?>{
        RadioServiceConstants.argChannelLabel: channelLabel,
        RadioServiceConstants.argSubtitle: subtitle,
      },
    );
    return RadioServiceStartInfo(
      pttActionEnabled:
          raw?[RadioServiceConstants.resultPttActionEnabled] == true,
    );
  }

  @override
  Future<void> stop() {
    return _methods.invokeMethod<void>(RadioServiceConstants.methodStop);
  }

  @override
  Future<void> setPhase(RadioTransportPhase phase) {
    return _methods.invokeMethod<void>(RadioServiceConstants.methodSetPhase, {
      RadioServiceConstants.argPhase: phase.wireName,
    });
  }

  @override
  Future<void> updateNotification({
    required String channelLabel,
    String? subtitle,
  }) {
    return _methods.invokeMethod<void>(
      RadioServiceConstants.methodUpdateNotification,
      <String, Object?>{
        RadioServiceConstants.argChannelLabel: channelLabel,
        RadioServiceConstants.argSubtitle: subtitle,
      },
    );
  }
}

/// In-memory double that mirrors the native wake-lock / audio-focus contract
/// so facade tests can fail if the mapping is inverted.
class FakeRadioServicePlatform implements RadioServicePlatform {
  final _events = StreamController<RadioServiceEvent>.broadcast();
  final calls = <String>[];

  bool running = false;
  bool userPowerOff = false;
  bool wakeLockHeld = false;
  bool audioFocusHeld = false;
  bool pttActionEnabled = true;
  bool killedDirty = false;
  RadioTransportPhase phase = RadioTransportPhase.idle;
  String? channelLabel;
  String? subtitle;
  Object? startError;

  @override
  Stream<RadioServiceEvent> get events => _events.stream;

  @override
  Future<RadioServiceStartInfo> start({
    required String channelLabel,
    String? subtitle,
  }) async {
    calls.add(RadioServiceConstants.methodStart);
    if (startError != null) throw startError!;
    running = true;
    userPowerOff = false;
    this.channelLabel = channelLabel;
    this.subtitle = subtitle;
    phase = RadioTransportPhase.idle;
    wakeLockHeld = false;
    audioFocusHeld = false;
    if (killedDirty) {
      killedDirty = false;
      _events.add(const RadioServiceKilled());
    }
    return RadioServiceStartInfo(pttActionEnabled: pttActionEnabled);
  }

  @override
  Future<void> stop() async {
    calls.add(RadioServiceConstants.methodStop);
    userPowerOff = true;
    _teardown();
  }

  @override
  Future<void> setPhase(RadioTransportPhase phase) async {
    calls.add('${RadioServiceConstants.methodSetPhase}:${phase.wireName}');
    if (!running) {
      throw StateError('setPhase requires an active start() session');
    }
    this.phase = phase;
    wakeLockHeld = phase != RadioTransportPhase.idle;
    switch (phase) {
      case RadioTransportPhase.rx:
        audioFocusHeld = true;
      case RadioTransportPhase.idle:
        audioFocusHeld = false;
      case RadioTransportPhase.tx:
        break;
    }
  }

  @override
  Future<void> updateNotification({
    required String channelLabel,
    String? subtitle,
  }) async {
    calls.add(RadioServiceConstants.methodUpdateNotification);
    if (!running) {
      throw StateError('updateNotification requires an active start() session');
    }
    this.channelLabel = channelLabel;
    this.subtitle = subtitle;
  }

  /// OEM/system death without [stop].
  void simulateOemKill() {
    killedDirty = true;
    running = false;
    wakeLockHeld = false;
    audioFocusHeld = false;
    _events.add(const RadioServiceKilled());
  }

  void simulatePttAction() => _events.add(const RadioServicePttAction());

  void simulatePowerOffAction() {
    userPowerOff = true;
    _teardown();
    _events.add(const RadioServicePowerOffAction());
  }

  void emit(RadioServiceEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();

  void _teardown() {
    running = false;
    phase = RadioTransportPhase.idle;
    wakeLockHeld = false;
    audioFocusHeld = false;
    killedDirty = false;
  }
}
