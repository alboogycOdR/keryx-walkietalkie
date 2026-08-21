import 'dart:async';
import 'dart:developer' as developer;

import 'radio_service_events.dart';
import 'radio_service_platform.dart';
import 'radio_transport_phase.dart';

/// Dart facade for the Android radio foreground service (KRX-080).
///
/// Event-driven: no timers, no polling. Native holds the FGS, notification,
/// wake lock and audio focus; this class pushes state and surfaces events.
abstract class RadioServiceController {
  Stream<RadioServiceEvent> get events;
  bool get isRunning;
  bool? get pttActionEnabled;

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
  Future<void> dispose();
}

class ChannelRadioServiceController implements RadioServiceController {
  ChannelRadioServiceController({RadioServicePlatform? platform})
    : _platform = platform ?? ChannelRadioServicePlatform();

  factory ChannelRadioServiceController.production() {
    return ChannelRadioServiceController();
  }

  final RadioServicePlatform _platform;
  final _events = StreamController<RadioServiceEvent>.broadcast();

  StreamSubscription<RadioServiceEvent>? _sub;
  bool _started = false;
  bool _disposed = false;
  bool _listening = false;
  bool? _pttActionEnabled;

  @override
  Stream<RadioServiceEvent> get events => _events.stream;

  @override
  bool get isRunning => _started;

  @override
  bool? get pttActionEnabled => _pttActionEnabled;

  @override
  Future<RadioServiceStartInfo> start({
    required String channelLabel,
    String? subtitle,
  }) async {
    _checkDisposed();
    final label = channelLabel.trim();
    if (label.isEmpty) {
      throw ArgumentError.value(
        channelLabel,
        'channelLabel',
        'must be non-empty',
      );
    }
    if (_started) {
      await stop();
    }
    _ensureSubscription();
    try {
      final info = await _platform.start(
        channelLabel: label,
        subtitle: subtitle,
      );
      _started = true;
      _pttActionEnabled = info.pttActionEnabled;
      return info;
    } catch (e, st) {
      developer.log(
        'radio service start failed: $e',
        name: 'keryx.radio_service',
        stackTrace: st,
      );
      _started = false;
      _pttActionEnabled = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    if (!_started) return;
    try {
      await _platform.stop();
    } catch (e, st) {
      developer.log(
        'radio service stop failed: $e',
        name: 'keryx.radio_service',
        stackTrace: st,
      );
    } finally {
      _started = false;
      _pttActionEnabled = null;
    }
  }

  @override
  Future<void> setPhase(RadioTransportPhase phase) async {
    _checkDisposed();
    if (!_started) {
      throw StateError('setPhase requires an active start() session');
    }
    await _platform.setPhase(phase);
  }

  @override
  Future<void> updateNotification({
    required String channelLabel,
    String? subtitle,
  }) async {
    _checkDisposed();
    final label = channelLabel.trim();
    if (label.isEmpty) {
      throw ArgumentError.value(
        channelLabel,
        'channelLabel',
        'must be non-empty',
      );
    }
    if (!_started) {
      throw StateError('updateNotification requires an active start() session');
    }
    await _platform.updateNotification(
      channelLabel: label,
      subtitle: subtitle,
    );
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _sub?.cancel();
    _sub = null;
    _listening = false;
    _disposed = true;
    await _events.close();
  }

  void _ensureSubscription() {
    if (_listening) return;
    _listening = true;
    _sub = _platform.events.listen(
      _onEvent,
      onError: (Object e) {
        developer.log(
          'radio service stream error: $e',
          name: 'keryx.radio_service',
        );
        _emit(RadioServiceFailed(e.toString()));
      },
    );
  }

  void _onEvent(RadioServiceEvent event) {
    if (event is RadioServiceKilled) {
      _started = false;
    }
    if (event is RadioServicePowerOffAction) {
      _started = false;
      _pttActionEnabled = null;
    }
    _emit(event);
  }

  void _emit(RadioServiceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _checkDisposed() {
    if (_disposed) {
      throw StateError('RadioServiceController is disposed');
    }
  }
}
