import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:keryx/core/state/radio_state.dart';

import 'livekit_adapter.dart';

const _logName = 'keryx.linked';

/// Watches a [LiveKitRoom]'s connection-state stream and turns it into the
/// reducer's link-state vocabulary (FR-045 / TS §8.4): `LinkDegraded` on
/// loss, `LinkResolved` on regain. Dispatches through the SAME
/// `RadioStateController.dispatch` ingress `RadioStateBridge` uses
/// (`lib/core/state/radio_state_bridge.dart`) — this is not a second
/// reducer entrypoint.
///
/// `link_lost`/`link_up` chirps and the `NO LINK` display flag are
/// projections of `RadioState.isNoLink` (TS §8.2: "UI, audio, haptics, and
/// network are all projections of it") — [LinkMonitor] only dispatches the
/// reducer event, it never plays audio directly.
///
/// Reconnects with exponential backoff while the link is down; on giving up
/// it dispatches `LinkResolved(useLocalFallback: true)` so the mode layer
/// auto-falls back to LOCAL — never a modal error dialog (FR-045).
class LinkMonitor {
  LinkMonitor({
    required LiveKitRoom room,
    required void Function(RadioEvent event) dispatch,
    Future<LiveKitRoom> Function()? reconnect,
    Duration initialBackoff = const Duration(seconds: 1),
    Duration maxBackoff = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) : _dispatch = dispatch,
       _reconnect = reconnect,
       _initialBackoff = initialBackoff,
       _maxBackoff = maxBackoff,
       _maxAttempts = maxAttempts {
    _attach(room);
  }

  final void Function(RadioEvent event) _dispatch;
  final Future<LiveKitRoom> Function()? _reconnect;
  final Duration _initialBackoff;
  final Duration _maxBackoff;
  final int _maxAttempts;

  StreamSubscription<LiveKitConnectionState>? _sub;
  Timer? _backoffTimer;
  bool _disposed = false;
  bool _degraded = false;
  int _attempt = 0;

  void _attach(LiveKitRoom room) {
    _sub?.cancel();
    _sub = room.connectionState.listen(
      _onState,
      onError: (Object error, StackTrace stack) {
        developer.log('link monitor: state stream error: $error', name: _logName, error: error, stackTrace: stack);
      },
    );
  }

  void _onState(LiveKitConnectionState state) {
    if (_disposed) return;
    switch (state) {
      case LiveKitConnectionState.connected:
        _attempt = 0;
        _backoffTimer?.cancel();
        if (_degraded) {
          _degraded = false;
          _dispatch(const LinkResolved());
        }
      case LiveKitConnectionState.connecting:
        break; // initial join — not a degradation from a prior connected state
      case LiveKitConnectionState.reconnecting:
      case LiveKitConnectionState.disconnected:
        _onLost();
    }
  }

  void _onLost() {
    if (!_degraded) {
      _degraded = true;
      _dispatch(const LinkDegraded());
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnect == null) return;
    if (_attempt >= _maxAttempts) {
      developer.log('link monitor: giving up after $_attempt attempts, falling back to LOCAL', name: _logName);
      _degraded = false;
      _dispatch(const LinkResolved(useLocalFallback: true));
      return;
    }
    final delayMs = math.min(
      _initialBackoff.inMilliseconds * math.pow(2, _attempt).toInt(),
      _maxBackoff.inMilliseconds,
    );
    _attempt++;
    _backoffTimer?.cancel();
    _backoffTimer = Timer(Duration(milliseconds: delayMs), _attemptReconnect);
  }

  Future<void> _attemptReconnect() async {
    if (_disposed) return;
    final reconnect = _reconnect;
    if (reconnect == null) return;
    try {
      final room = await reconnect();
      if (_disposed) return;
      _attach(room);
    } on Object catch (error, stack) {
      developer.log('link monitor: reconnect attempt failed: $error', name: _logName, error: error, stackTrace: stack);
      _scheduleReconnect();
    }
  }

  /// Whether the monitor currently considers the link down.
  bool get isDegraded => _degraded;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _backoffTimer?.cancel();
    unawaited(_sub?.cancel());
  }
}
