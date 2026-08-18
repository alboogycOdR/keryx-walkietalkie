import 'dart:async';
import 'dart:developer' as developer;

import 'broadcast_fallback.dart';
import 'discovered_peer.dart';
import 'discovery_config.dart';
import 'discovery_scheduler.dart';
import 'discovery_state.dart';
import 'nsd_events.dart';
import 'nsd_platform.dart';

/// LOCAL discovery facade: NSD + MulticastLock + UDP fallback + `LAN?`.
abstract class DiscoveryService {
  Stream<DiscoveredPeer> get peersFound;
  Stream<DiscoveredPeer> get peersLost;
  Stream<DiscoveryState> get states;
  DiscoveryState get state;

  Future<void> start(DiscoveryConfig config);
  Future<void> onTuned();
  Future<void> stop();
  Future<void> dispose();
}

class NsdDiscoveryService implements DiscoveryService {
  NsdDiscoveryService({
    required NsdPlatform platform,
    required BeaconTransport beaconTransport,
    required DiscoveryScheduler scheduler,
  }) : _platform = platform,
       _transport = beaconTransport,
       _scheduler = scheduler;

  factory NsdDiscoveryService.production() {
    return NsdDiscoveryService(
      platform: ChannelNsdPlatform(),
      beaconTransport: UdpBeaconTransport(),
      scheduler: TimerDiscoveryScheduler(),
    );
  }

  final NsdPlatform _platform;
  final BeaconTransport _transport;
  final DiscoveryScheduler _scheduler;

  late final BroadcastFallback _fallback = BroadcastFallback(
    transport: _transport,
    scheduler: _scheduler,
    onPeer: _onBeaconPeer,
    onWindowElapsed: _onBeaconWindowElapsed,
    onError: _onBeaconError,
  );

  final _found = StreamController<DiscoveredPeer>.broadcast();
  final _lost = StreamController<DiscoveredPeer>.broadcast();
  final _states = StreamController<DiscoveryState>.broadcast();

  StreamSubscription<NsdEvent>? _nsdSub;
  DiscoveryConfig? _config;
  DiscoveryState _state = DiscoveryState.idle;
  bool _nsdRegistered = false;
  bool _nsdBrowsing = false;
  bool _disposed = false;
  var _listening = false;

  @override
  Stream<DiscoveredPeer> get peersFound => _found.stream;

  @override
  Stream<DiscoveredPeer> get peersLost => _lost.stream;

  @override
  Stream<DiscoveryState> get states => _states.stream;

  @override
  DiscoveryState get state => _state;

  @override
  Future<void> start(DiscoveryConfig config) async {
    _checkDisposed();
    config.validate();
    await stop();
    _config = config;
    _nsdRegistered = false;
    _nsdBrowsing = false;
    _ensureNsdSubscription();
    _emit(
      DiscoveryState.idle.copyWith(radioOn: true, beaconWindowElapsed: false),
    );

    try {
      await _platform.start(config);
    } catch (e, st) {
      developer.log(
        'nsd start failed: $e',
        name: 'keryx.discovery',
        stackTrace: st,
      );
      _emit(_state.copyWith(nsdFailed: true, nsdActive: false));
      _recomputeLanTrouble();
    }
  }

  /// Starts (or restarts) the 30 s UDP beacon window after a tune.
  @override
  Future<void> onTuned() async {
    _checkDisposed();
    final config = _config;
    if (config == null || !_state.radioOn) {
      throw StateError('onTuned requires an active start() session');
    }
    _emit(
      _state.copyWith(
        beaconActive: true,
        beaconWindowElapsed: false,
        lanTrouble: false,
      ),
    );
    try {
      await _fallback.start(config);
    } catch (e, st) {
      developer.log(
        'beacon start failed: $e',
        name: 'keryx.discovery',
        stackTrace: st,
      );
      _emit(_state.copyWith(beaconActive: false, beaconWindowElapsed: true));
      _recomputeLanTrouble();
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    await _fallback.stop();
    if (_state.radioOn) {
      try {
        await _platform.stop();
      } catch (e, st) {
        developer.log(
          'nsd stop failed: $e',
          name: 'keryx.discovery',
          stackTrace: st,
        );
      }
    }
    _config = null;
    _nsdRegistered = false;
    _nsdBrowsing = false;
    _emit(DiscoveryState.idle);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _nsdSub?.cancel();
    _nsdSub = null;
    _listening = false;
    _disposed = true;
    await _found.close();
    await _lost.close();
    await _states.close();
  }

  void _ensureNsdSubscription() {
    if (_listening) return;
    _listening = true;
    _nsdSub = _platform.events.listen(
      _onNsdEvent,
      onError: (Object e) {
        developer.log('nsd stream error: $e', name: 'keryx.discovery');
        _emit(_state.copyWith(nsdFailed: true, nsdActive: false));
        _recomputeLanTrouble();
      },
    );
  }

  void _onNsdEvent(NsdEvent event) {
    switch (event) {
      case NsdRegistered():
        _nsdRegistered = true;
        _emit(
          _state.copyWith(
            nsdActive: _nsdRegistered && _nsdBrowsing,
            nsdFailed: false,
          ),
        );
      case NsdBrowseStarted():
        _nsdBrowsing = true;
        _emit(
          _state.copyWith(
            nsdActive: _nsdRegistered && _nsdBrowsing,
            nsdFailed: false,
          ),
        );
      case NsdLockChanged(:final held):
        _emit(_state.copyWith(multicastLockHeld: held));
      case NsdPeerFound(:final peer):
        _emit(_state.copyWith(heardAnyDiscoveryTraffic: true));
        _maybeAddPeer(peer);
      case NsdPeerLost(:final serviceName):
        _removePeer(serviceName);
      case NsdFailed(:final message):
        developer.log('nsd failed: $message', name: 'keryx.discovery');
        _emit(_state.copyWith(nsdFailed: true, nsdActive: false));
        _recomputeLanTrouble();
    }
  }

  void _onBeaconPeer(DiscoveredPeer peer) {
    _emit(_state.copyWith(heardAnyDiscoveryTraffic: true, lanTrouble: false));
    _maybeAddPeer(peer);
  }

  void _onBeaconWindowElapsed() {
    _emit(_state.copyWith(beaconActive: false, beaconWindowElapsed: true));
    _recomputeLanTrouble();
  }

  void _onBeaconError(Object error) {
    developer.log('beacon error: $error', name: 'keryx.discovery');
    _recomputeLanTrouble();
  }

  void _maybeAddPeer(DiscoveredPeer peer) {
    final config = _config;
    if (config == null) return;
    if (peer.peerId != null && peer.peerId == config.peerId) return;
    if (!peer.matchesChannel(config.channelHashPrefix)) return;
    if (peer.version != config.protocolVersion) return;
    final next = [..._state.peers];
    final idx = next.indexWhere(
      (p) => p.peerId != null && p.peerId == peer.peerId,
    );
    if (idx >= 0) {
      next[idx] = peer;
    } else {
      next.add(peer);
      if (!_found.isClosed) _found.add(peer);
    }
    _emit(_state.copyWith(peers: List.unmodifiable(next), lanTrouble: false));
  }

  void _removePeer(String serviceName) {
    final idx = _state.peers.indexWhere((p) => p.peerId == serviceName);
    if (idx < 0) return;
    final gone = _state.peers[idx];
    final next = [..._state.peers]..removeAt(idx);
    if (!_lost.isClosed) _lost.add(gone);
    _emit(_state.copyWith(peers: List.unmodifiable(next)));
  }

  void _recomputeLanTrouble() {
    if (!_state.radioOn) {
      _emit(_state.copyWith(lanTrouble: false));
      return;
    }
    // Both paths failed to prove the LAN is open: NSD hard-failed (or never
    // became active) AND the 30 s beacon window ended with no Keryx traffic.
    final nsdDead = _state.nsdFailed || !_state.nsdActive;
    final udpDead =
        _state.beaconWindowElapsed && !_state.heardAnyDiscoveryTraffic;
    final trouble = nsdDead && udpDead && _state.peers.isEmpty;
    _emit(_state.copyWith(lanTrouble: trouble));
  }

  void _emit(DiscoveryState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('DiscoveryService is disposed');
  }
}
