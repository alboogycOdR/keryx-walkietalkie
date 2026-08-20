import 'dart:async';
import 'dart:developer' as developer;

import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/discovery/discovery_service.dart';

import 'peer_session.dart';
import 'signaling_channel.dart';
import 'signaling_config.dart';
import 'signaling_envelope.dart';
import 'signaling_state.dart';

/// LOCAL signaling: LAN WebSocket sessions, offer/answer/ICE relay,
/// PRESENCE-based departure, 16-peer soft cap.
///
/// Media and [FloorTransport] are TASK-021. This class never opens
/// NSD or invents peer addresses — it consumes [DiscoveredPeer.host]
/// / `.port` and exposes [boundPort] for `DiscoveryConfig.signalingPort`.
class SignalingService {
  SignalingService({
    required SignalingEndpoint endpoint,
    required FloorClock clock,
    Stream<DiscoveredPeer>? peersFound,
    Stream<DiscoveredPeer>? peersLost,
  }) : _endpoint = endpoint,
       _clock = clock {
    if (peersFound != null) {
      _foundSub = peersFound.listen(onPeerFound);
    }
    if (peersLost != null) {
      _lostSub = peersLost.listen(onPeerLost);
    }
  }

  final SignalingEndpoint _endpoint;
  final FloorClock _clock;

  final _states = StreamController<SignalingState>.broadcast();
  final _joined = StreamController<PeerSession>.broadcast();
  final _departed = StreamController<PeerSession>.broadcast();
  final _signals = StreamController<SignalingEnvelope>.broadcast();

  final _links = <_LiveLink>[];
  final _byPeer = <String, _LiveLink>{};
  final _dialing = <String>{};

  StreamSubscription<DiscoveredPeer>? _foundSub;
  StreamSubscription<DiscoveredPeer>? _lostSub;
  StreamSubscription<SignalingChannel>? _acceptSub;

  SignalingConfig? _config;
  SignalingState _state = SignalingState.idle;
  bool _disposed = false;

  SignalingState get state => _state;

  Stream<SignalingState> get states => _states.stream;

  Stream<PeerSession> get sessionsJoined => _joined.stream;

  Stream<PeerSession> get sessionsDeparted => _departed.stream;

  /// Offer / answer / LAN ICE from established peers (TASK-021 consumes).
  Stream<SignalingEnvelope> get incomingSignals => _signals.stream;

  /// Port to pass into `DiscoveryConfig.signalingPort`. `0` before [start].
  int get boundPort => _endpoint.port;

  Future<void> start(SignalingConfig config) async {
    _checkDisposed();
    config.validate();
    await stop();
    _config = config;
    await _endpoint.bind();
    _acceptSub = _endpoint.incoming.listen(
      _onInbound,
      onError: (Object e, StackTrace st) {
        developer.log(
          'signaling accept error: $e',
          name: 'keryx.signaling',
          stackTrace: st,
        );
      },
    );
    _emit(
      SignalingState(
        running: true,
        boundPort: _endpoint.port,
        sessions: const [],
      ),
    );
    developer.log(
      'signaling started peer=${config.peerId} port=${_endpoint.port}',
      name: 'keryx.signaling',
    );
  }

  /// Subscribe to a TASK-019 facade. Safe to call more than once (replaces).
  void attachDiscovery(DiscoveryService discovery) {
    _checkDisposed();
    _foundSub?.cancel();
    _lostSub?.cancel();
    _foundSub = discovery.peersFound.listen(onPeerFound);
    _lostSub = discovery.peersLost.listen(onPeerLost);
  }

  /// Dial or wait, per the lower-peerId-dials rule.
  void onPeerFound(DiscoveredPeer peer) {
    if (_disposed) return;
    final config = _config;
    if (config == null || !_state.running) return;
    final peerId = peer.peerId;
    if (peerId == null || peerId.isEmpty) return;
    if (peerId == config.peerId) return;
    if (!peer.matchesChannel(config.channelHashPrefix)) return;
    if (peer.version != config.protocolVersion) return;
    if (_byPeer.containsKey(peerId) || _dialing.contains(peerId)) return;

    final host = peer.host;
    if (host == null || host.isEmpty) {
      developer.log(
        'skip dial $peerId: discovery host missing',
        name: 'keryx.signaling',
      );
      return;
    }

    // Lower peerId dials; higher listens. Deterministic, no double socket.
    if (config.peerId.compareTo(peerId) < 0) {
      unawaited(_dial(peerId, host, peer.port));
    }
  }

  /// Discovery lost → tear the session down immediately (in addition to
  /// PRESENCE-miss departure).
  void onPeerLost(DiscoveredPeer peer) {
    if (_disposed) return;
    final peerId = peer.peerId;
    if (peerId == null) return;
    final link = _byPeer[peerId];
    if (link != null) {
      unawaited(_closeLink(link, departed: true));
    }
  }

  /// Relay an offer/answer/ICE envelope to an established peer.
  ///
  /// Returns `false` if there is no session, the envelope is not LAN-legal,
  /// or the service is stopped. Non-LAN ICE is dropped, never sent.
  bool sendSignal(SignalingEnvelope envelope) {
    if (_disposed || !_state.running) return false;
    final config = _config;
    if (config == null) return false;
    if (envelope.from != config.peerId) {
      throw ArgumentError.value(
        envelope.from,
        'from',
        'must be the local peerId',
      );
    }
    if (envelope.type != SignalingType.offer &&
        envelope.type != SignalingType.answer &&
        envelope.type != SignalingType.iceCandidate) {
      throw ArgumentError.value(
        envelope.type,
        'type',
        'only offer/answer/ice-candidate may be sent via sendSignal',
      );
    }
    final link = _byPeer[envelope.to];
    if (link == null || !link.established) return false;
    final filtered = envelope.lanFiltered();
    if (filtered == null) {
      developer.log(
        'dropped non-LAN ICE to ${envelope.to}',
        name: 'keryx.signaling',
      );
      return false;
    }
    _sendRaw(link, filtered.encode());
    return true;
  }

  Future<void> stop() async {
    if (_disposed) return;
    final links = List<_LiveLink>.of(_links);
    for (final link in links) {
      await _closeLink(link, departed: false);
    }
    await _acceptSub?.cancel();
    _acceptSub = null;
    _config = null;
    _dialing.clear();
    _emit(SignalingState.idle.copyWith(boundPort: 0));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    await _foundSub?.cancel();
    await _lostSub?.cancel();
    _foundSub = null;
    _lostSub = null;
    _disposed = true;
    await _states.close();
    await _joined.close();
    await _departed.close();
    await _signals.close();
  }

  Future<void> _dial(String peerId, String host, int port) async {
    _dialing.add(peerId);
    try {
      final channel = await _endpoint.connect(host, port);
      if (_disposed || !_state.running || _byPeer.containsKey(peerId)) {
        await channel.close();
        return;
      }
      _attach(
        channel,
        expectedPeerId: peerId,
        host: host,
        port: port,
        outbound: true,
      );
    } catch (e, st) {
      developer.log(
        'dial $peerId at $host:$port failed: $e',
        name: 'keryx.signaling',
        stackTrace: st,
      );
    } finally {
      _dialing.remove(peerId);
    }
  }

  void _onInbound(SignalingChannel channel) {
    if (_disposed || !_state.running) {
      unawaited(channel.close());
      return;
    }
    _attach(
      channel,
      expectedPeerId: null,
      host: channel.remoteLabel,
      port: 0,
      outbound: false,
    );
  }

  void _attach(
    SignalingChannel channel, {
    required String? expectedPeerId,
    required String host,
    required int port,
    required bool outbound,
  }) {
    final link = _LiveLink(
      channel: channel,
      expectedPeerId: expectedPeerId,
      host: host,
      port: port,
    );
    _links.add(link);
    link.sub = channel.incoming.listen(
      (text) => _onText(link, text),
      onError: (Object e, StackTrace st) {
        developer.log(
          'session error: $e',
          name: 'keryx.signaling',
          stackTrace: st,
        );
        unawaited(_closeLink(link, departed: true));
      },
      onDone: () {
        unawaited(_closeLink(link, departed: true));
      },
    );
    link.handshakeTimeout = _clock.schedule(FloorTiming.presenceDeparture, () {
      if (!link.established) {
        developer.log(
          'handshake timeout ${expectedPeerId ?? channel.remoteLabel}',
          name: 'keryx.signaling',
        );
        unawaited(_closeLink(link, departed: false));
      }
    });
    if (outbound) {
      _sendHello(link, SignalingType.hello, to: expectedPeerId ?? '');
    }
  }

  void _onText(_LiveLink link, String text) {
    if (link.closed) return;
    final floor = FloorCodec.decode(text);
    if (floor != null) {
      if (floor is Presence) {
        _onPresence(link, floor);
      }
      return;
    }
    final envelope = SignalingEnvelope.decode(text);
    if (envelope == null) return;
    switch (envelope.type) {
      case SignalingType.hello:
        _onHello(link, envelope, replyOk: true);
      case SignalingType.helloOk:
        _onHello(link, envelope, replyOk: false);
      case SignalingType.offer:
      case SignalingType.answer:
      case SignalingType.iceCandidate:
        _onSignal(link, envelope);
    }
  }

  void _onHello(
    _LiveLink link,
    SignalingEnvelope envelope, {
    required bool replyOk,
  }) {
    final config = _config;
    if (config == null) return;
    if (envelope.channelHash != config.channelHashPrefix) {
      developer.log(
        'handshake channel mismatch from ${envelope.from}',
        name: 'keryx.signaling',
      );
      unawaited(_closeLink(link, departed: false));
      return;
    }
    if (envelope.to.isNotEmpty && envelope.to != config.peerId) {
      unawaited(_closeLink(link, departed: false));
      return;
    }
    if (envelope.from == config.peerId) {
      unawaited(_closeLink(link, departed: false));
      return;
    }
    final expected = link.expectedPeerId;
    if (expected != null && expected != envelope.from) {
      unawaited(_closeLink(link, departed: false));
      return;
    }
    if (_byPeer.containsKey(envelope.from) && _byPeer[envelope.from] != link) {
      // Duplicate socket for an already-sessioned peer.
      unawaited(_closeLink(link, departed: false));
      return;
    }
    if (replyOk && !link.established) {
      _sendHello(link, SignalingType.helloOk, to: envelope.from);
    }
    _establish(link, envelope.from, envelope.callsign ?? '');
  }

  void _establish(_LiveLink link, String peerId, String callsign) {
    if (link.closed || link.established) return;
    final config = _config;
    if (config == null) return;
    link.established = true;
    link.peerId = peerId;
    link.callsign = callsign;
    link.handshakeTimeout?.cancel();
    link.handshakeTimeout = null;
    _byPeer[peerId] = link;
    final session = PeerSession(
      peerId: peerId,
      callsign: callsign,
      host: link.host,
      port: link.port,
      lastPresenceAt: _clock.now(),
    );
    link.session = session;
    _publishSessions();
    if (!_joined.isClosed) _joined.add(session);
    _sendPresence(link);
    _armHeartbeat(link);
  }

  void _onPresence(_LiveLink link, Presence presence) {
    if (!link.established || link.peerId != presence.peer) return;
    final session = link.session;
    if (session == null) return;
    session.lastPresenceAt = _clock.now();
    session.lastSeq = presence.seq;
    if (presence.cs.isNotEmpty) {
      session.callsign = presence.cs;
      link.callsign = presence.cs;
    }
    _publishSessions();
  }

  void _onSignal(_LiveLink link, SignalingEnvelope envelope) {
    if (!link.established) return;
    final config = _config;
    if (config == null) return;
    if (envelope.from != link.peerId) return;
    if (envelope.to != config.peerId) return;
    final filtered = envelope.lanFiltered();
    if (filtered == null) {
      developer.log(
        'dropped non-LAN ICE from ${envelope.from}',
        name: 'keryx.signaling',
      );
      return;
    }
    if (!_signals.isClosed) _signals.add(filtered);
  }

  void _armHeartbeat(_LiveLink link) {
    link.heartbeat?.cancel();
    link.heartbeat = _clock.schedule(FloorTiming.presenceHeartbeat, () {
      if (link.closed || !link.established) return;
      _sendPresence(link);
      _checkDeparture(link);
      if (!link.closed && link.established) _armHeartbeat(link);
    });
  }

  void _sendPresence(_LiveLink link) {
    final config = _config;
    if (config == null || link.closed) return;
    link.outSeq += 1;
    final wire = FloorCodec.encode(
      Presence(peer: config.peerId, cs: config.callsign, seq: link.outSeq),
    );
    _sendRaw(link, wire);
  }

  void _checkDeparture(_LiveLink link) {
    final session = link.session;
    if (session == null) return;
    final age = _clock.now().difference(session.lastPresenceAt);
    if (age >= FloorTiming.presenceDeparture) {
      developer.log(
        'presence miss → departed ${link.peerId}',
        name: 'keryx.signaling',
      );
      unawaited(_closeLink(link, departed: true));
    }
  }

  void _sendHello(_LiveLink link, SignalingType type, {required String to}) {
    final config = _config;
    if (config == null) return;
    final envelope = SignalingEnvelope(
      type: type,
      from: config.peerId,
      to: to,
      payload: {'cs': config.callsign, 'ch': config.channelHashPrefix},
    );
    _sendRaw(link, envelope.encode());
  }

  void _sendRaw(_LiveLink link, String text) {
    try {
      link.channel.send(text);
    } catch (e, st) {
      developer.log('send failed: $e', name: 'keryx.signaling', stackTrace: st);
      unawaited(_closeLink(link, departed: true));
    }
  }

  Future<void> _closeLink(_LiveLink link, {required bool departed}) async {
    if (link.closed) return;
    link.closed = true;
    link.handshakeTimeout?.cancel();
    link.heartbeat?.cancel();
    await link.sub?.cancel();
    try {
      await link.channel.close();
    } on Object {
      // Already closed.
    }
    _links.remove(link);
    final peerId = link.peerId;
    if (peerId != null && _byPeer[peerId] == link) {
      _byPeer.remove(peerId);
    }
    final session = link.session;
    if (departed && session != null && !_departed.isClosed) {
      _departed.add(session);
    }
    _publishSessions();
  }

  void _publishSessions() {
    if (!_state.running) {
      _emit(SignalingState.idle);
      return;
    }
    final sessions = _links
        .where((l) => l.established && l.session != null)
        .map((l) => l.session!)
        .toList(growable: false);
    _emit(
      SignalingState(
        running: true,
        boundPort: _endpoint.port,
        sessions: List.unmodifiable(sessions),
      ),
    );
  }

  void _emit(SignalingState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('SignalingService is disposed');
  }
}

class _LiveLink {
  _LiveLink({
    required this.channel,
    required this.expectedPeerId,
    required this.host,
    required this.port,
  });

  final SignalingChannel channel;
  final String? expectedPeerId;
  final String host;
  final int port;

  StreamSubscription<String>? sub;
  FloorTimer? heartbeat;
  FloorTimer? handshakeTimeout;
  PeerSession? session;
  String? peerId;
  String callsign = '';
  int outSeq = 0;
  bool established = false;
  bool closed = false;
}
