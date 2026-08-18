import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'discovered_peer.dart';
import 'discovery_config.dart';
import 'discovery_constants.dart';
import 'discovery_scheduler.dart';

/// Sends/receives the Keryx UDP beacon payload. Injected so tests stay dry.
abstract class BeaconTransport {
  Future<void> start({
    required DiscoveryConfig self,
    required void Function(DiscoveredPeer peer) onPeer,
    required void Function(Object error) onError,
  });

  /// Transmit one beacon. No-op if not started.
  void send();

  Future<void> stop();
}

/// JSON beacon: `{v,t,peer,cs,ch,p}` — same privacy fields as NSD TXT.
class UdpBeaconTransport implements BeaconTransport {
  UdpBeaconTransport({
    this.port = DiscoveryConstants.beaconPort,
    this.bindAddress,
  });

  final int port;
  final InternetAddress? bindAddress;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  DiscoveryConfig? _self;
  void Function(DiscoveredPeer peer)? _onPeer;

  static const String type = 'BEACON';

  @override
  Future<void> start({
    required DiscoveryConfig self,
    required void Function(DiscoveredPeer peer) onPeer,
    required void Function(Object error) onError,
  }) async {
    await stop();
    _self = self;
    _onPeer = onPeer;
    try {
      final socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _socket = socket;
      _sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          _read(socket);
        }
      }, onError: onError);
    } catch (e, st) {
      developer.log(
        'UDP beacon bind failed: $e',
        name: 'keryx.discovery',
        stackTrace: st,
      );
      onError(e);
      rethrow;
    }
  }

  void _read(RawDatagramSocket socket) {
    final dg = socket.receive();
    if (dg == null) return;
    final peer = decodeBeacon(dg.data, host: dg.address.address);
    if (peer == null) return;
    if (peer.peerId != null && peer.peerId == _self?.peerId) return;
    _onPeer?.call(peer);
  }

  @override
  void send() {
    final socket = _socket;
    final self = _self;
    if (socket == null || self == null) return;
    final bytes = encodeBeacon(self);
    socket.send(bytes, InternetAddress('255.255.255.255'), port);
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    _self = null;
    _onPeer = null;
  }

  static List<int> encodeBeacon(DiscoveryConfig self) {
    return utf8.encode(
      jsonEncode({
        'v': self.protocolVersion,
        't': type,
        'peer': self.peerId,
        'cs': self.callsign,
        'ch': self.channelHashPrefix,
        'p': self.signalingPort,
      }),
    );
  }

  static DiscoveredPeer? decodeBeacon(List<int> bytes, {String? host}) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['t'] != type) return null;
      final v = map['v'];
      if (v is! int || v != DiscoveryConstants.protocolVersion) return null;
      final cs = map['cs'];
      final ch = map['ch'];
      final p = map['p'];
      final peer = map['peer'];
      if (cs is! String || cs.isEmpty) return null;
      if (ch is! String || ch.isEmpty) return null;
      if (p is! int || p < 1 || p > 65535) return null;
      if (peer is! String || peer.isEmpty) return null;
      return DiscoveredPeer(
        peerId: peer,
        callsign: cs,
        channelHashPrefix: ch,
        version: v,
        host: host,
        port: p,
        source: DiscoverySource.udp,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Drives the 2 s × 30 s post-tune window over a [BeaconTransport].
class BroadcastFallback {
  BroadcastFallback({
    required BeaconTransport transport,
    required DiscoveryScheduler scheduler,
    required void Function(DiscoveredPeer peer) onPeer,
    required void Function() onWindowElapsed,
    required void Function(Object error) onError,
  }) : _transport = transport,
       _scheduler = scheduler,
       _onPeer = onPeer,
       _onWindowElapsed = onWindowElapsed,
       _onError = onError;

  final BeaconTransport _transport;
  final DiscoveryScheduler _scheduler;
  final void Function(DiscoveredPeer peer) _onPeer;
  final void Function() _onWindowElapsed;
  final void Function(Object error) _onError;

  bool get isActive => _active;
  bool _active = false;

  Future<void> start(DiscoveryConfig self) async {
    await stop();
    _active = true;
    try {
      await _transport.start(self: self, onPeer: _onPeer, onError: _onError);
    } catch (e) {
      _active = false;
      rethrow;
    }
    _scheduler.periodic(DiscoveryConstants.beaconInterval, () {
      if (_active) _transport.send();
    });
    _scheduler.once(DiscoveryConstants.beaconWindow, () {
      _active = false;
      _scheduler.cancelAll();
      _onWindowElapsed();
    });
  }

  Future<void> stop() async {
    _active = false;
    _scheduler.cancelAll();
    await _transport.stop();
  }
}
