import 'dart:async';

import 'package:flutter/services.dart';

import 'discovery_config.dart';
import 'discovery_constants.dart';
import 'nsd_events.dart';

/// Native NSD + MulticastLock. Production impl is a Method/Event channel.
abstract class NsdPlatform {
  Future<void> start(DiscoveryConfig config);
  Future<void> stop();
  Stream<NsdEvent> get events;
}

class ChannelNsdPlatform implements NsdPlatform {
  ChannelNsdPlatform({MethodChannel? methods, EventChannel? events})
    : _methods =
          methods ?? const MethodChannel(DiscoveryConstants.methodChannel),
      _events = events ?? const EventChannel(DiscoveryConstants.eventChannel);

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<NsdEvent>? _parsed;

  @override
  Stream<NsdEvent> get events {
    return _parsed ??= _events.receiveBroadcastStream().map((raw) {
      if (raw is! Map) return const NsdFailed('malformed nsd event');
      return nsdEventFromMap(raw) ?? const NsdFailed('unknown nsd event');
    });
  }

  @override
  Future<void> start(DiscoveryConfig config) {
    config.validate();
    return _methods.invokeMethod<void>(
      DiscoveryConstants.methodStart,
      config.toPlatformArgs(),
    );
  }

  @override
  Future<void> stop() {
    return _methods.invokeMethod<void>(DiscoveryConstants.methodStop);
  }
}

/// In-memory NSD double for facade tests.
class FakeNsdPlatform implements NsdPlatform {
  final _events = StreamController<NsdEvent>.broadcast();
  final startedArgs = <Map<String, Object>>[];
  int stopCount = 0;
  Object? startError;
  bool started = false;

  @override
  Stream<NsdEvent> get events => _events.stream;

  @override
  Future<void> start(DiscoveryConfig config) async {
    config.validate();
    startedArgs.add(config.toPlatformArgs());
    if (startError != null) {
      throw startError!;
    }
    started = true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    started = false;
  }

  void emit(NsdEvent event) => _events.add(event);

  Future<void> dispose() => _events.close();
}
