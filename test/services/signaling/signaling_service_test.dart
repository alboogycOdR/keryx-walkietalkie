import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/signaling/signaling.dart';

const _ch = 'aabbccdd';
const _alpha = 'aaaaaaaaaa';
const _bravo = 'bbbbbbbbbb';

SignalingConfig _cfg(String peerId, {String ch = _ch, String cs = 'BRAVO-7'}) {
  return SignalingConfig(peerId: peerId, callsign: cs, channelHashPrefix: ch);
}

DiscoveredPeer _peer({
  required String id,
  required int port,
  String host = '10.0.0.8',
  String ch = _ch,
}) {
  return DiscoveredPeer(
    peerId: id,
    callsign: 'STN',
    channelHashPrefix: ch,
    version: 1,
    host: host,
    port: port,
  );
}

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InProcessSignalingHub hub;
  late VirtualClock clock;
  late InProcessSignalingEndpoint epA;
  late InProcessSignalingEndpoint epB;
  late SignalingService a;
  late SignalingService b;

  setUp(() {
    hub = InProcessSignalingHub();
    clock = VirtualClock();
    epA = hub.endpoint();
    epB = hub.endpoint();
    a = SignalingService(endpoint: epA, clock: clock);
    b = SignalingService(endpoint: epB, clock: clock);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await epA.close();
    await epB.close();
  });

  Future<void> startPair() async {
    await a.start(_cfg(_alpha, cs: 'ALPHA-1'));
    await b.start(_cfg(_bravo, cs: 'BRAVO-7'));
  }

  Future<void> joinPair() async {
    await startPair();
    a.onPeerFound(_peer(id: _bravo, port: b.boundPort));
    b.onPeerFound(_peer(id: _alpha, port: a.boundPort));
    await flush();
  }

  test('IoSignalingEndpoint bind is loopback-free', () {
    expect(IoSignalingEndpoint.lanBindAddress, InternetAddress.anyIPv4);
    expect(IoSignalingEndpoint.lanBindAddress.isLoopback, isFalse);
    expect(
      IoSignalingEndpoint(bindAddress: InternetAddress.loopbackIPv4).bind(),
      throwsStateError,
    );
  });

  test(
    'start binds an ephemeral port for DiscoveryConfig.signalingPort',
    () async {
      await a.start(_cfg(_alpha));
      expect(a.state.running, isTrue);
      expect(a.boundPort, greaterThan(0));
      expect(a.state.boundPort, a.boundPort);
    },
  );

  test('matching-channel peers handshake; lower peerId dials once', () async {
    final joinedA = <PeerSession>[];
    final joinedB = <PeerSession>[];
    a.sessionsJoined.listen(joinedA.add);
    b.sessionsJoined.listen(joinedB.add);

    await joinPair();

    expect(a.state.peerCount, 1);
    expect(b.state.peerCount, 1);
    expect(a.state.sessions.single.peerId, _bravo);
    expect(b.state.sessions.single.peerId, _alpha);
    expect(joinedA.map((s) => s.peerId), [_bravo]);
    expect(joinedB.map((s) => s.peerId), [_alpha]);
    expect(a.state.capWarning, isFalse);
  });

  test('channel-hash mismatch closes without a session', () async {
    await a.start(_cfg(_alpha, ch: 'aaaaaaaa'));
    await b.start(_cfg(_bravo, ch: 'bbbbbbbb'));
    // Lie about the remote prefix so A will dial; B rejects the hello.
    a.onPeerFound(_peer(id: _bravo, port: b.boundPort, ch: 'aaaaaaaa'));
    await flush();
    expect(a.state.peerCount, 0);
    expect(b.state.peerCount, 0);
  });

  test('skips self, missing host, and other-channel peers', () async {
    await startPair();
    a.onPeerFound(_peer(id: _alpha, port: b.boundPort));
    a.onPeerFound(
      DiscoveredPeer(
        peerId: _bravo,
        callsign: 'STN',
        channelHashPrefix: _ch,
        version: 1,
        host: null,
        port: b.boundPort,
      ),
    );
    a.onPeerFound(_peer(id: _bravo, port: b.boundPort, ch: 'ffffffff'));
    await flush();
    expect(a.state.peerCount, 0);
  });

  test('offer/answer relay and LAN ICE; non-LAN ICE dropped', () async {
    final signalsB = <SignalingEnvelope>[];
    b.incomingSignals.listen(signalsB.add);
    await joinPair();

    final offer = SignalingEnvelope(
      type: SignalingType.offer,
      from: _alpha,
      to: _bravo,
      payload: {
        'sdp':
            'v=0\na=candidate:0 1 UDP 2122260223 10.0.0.8 9 typ host\n'
            'a=candidate:2 1 UDP 1 203.0.113.9 9 typ srflx\n',
      },
    );
    expect(a.sendSignal(offer), isTrue);
    await flush();
    expect(signalsB, hasLength(1));
    expect(signalsB.single.type, SignalingType.offer);
    expect(signalsB.single.sdp, contains('typ host'));
    expect(signalsB.single.sdp, isNot(contains('typ srflx')));

    final relayIce = SignalingEnvelope(
      type: SignalingType.iceCandidate,
      from: _alpha,
      to: _bravo,
      payload: {'candidate': 'candidate:3 1 UDP 41819903 1.1.1.1 9 typ relay'},
    );
    expect(a.sendSignal(relayIce), isFalse);
    await flush();
    expect(signalsB, hasLength(1));

    final hostIce = SignalingEnvelope(
      type: SignalingType.iceCandidate,
      from: _alpha,
      to: _bravo,
      payload: {
        'candidate': 'candidate:0 1 UDP 2122260223 10.0.0.8 9 typ host',
      },
    );
    expect(a.sendSignal(hostIce), isTrue);
    await flush();
    expect(signalsB, hasLength(2));
    expect(signalsB.last.type, SignalingType.iceCandidate);
  });

  test('3 presence misses (15 s) = departed', () async {
    final departed = <PeerSession>[];
    a.sessionsDeparted.listen(departed.add);

    // B uses a frozen clock so it never heartbeats after the hello-time send.
    final clockB = VirtualClock();
    await b.dispose();
    await epB.close();
    epB = hub.endpoint();
    b = SignalingService(endpoint: epB, clock: clockB);

    await a.start(_cfg(_alpha, cs: 'ALPHA-1'));
    await b.start(_cfg(_bravo, cs: 'BRAVO-7'));
    a.onPeerFound(_peer(id: _bravo, port: b.boundPort));
    await flush();
    expect(a.state.peerCount, 1);

    clock.elapse(FloorTiming.presenceHeartbeat);
    await flush();
    expect(a.state.peerCount, 1);

    clock.elapse(FloorTiming.presenceHeartbeat);
    await flush();
    expect(a.state.peerCount, 1);

    clock.elapse(FloorTiming.presenceHeartbeat);
    await flush();
    expect(a.state.peerCount, 0);
    expect(departed.map((s) => s.peerId), [_bravo]);
  });

  test('peersLost tears the session down', () async {
    final departed = <PeerSession>[];
    a.sessionsDeparted.listen(departed.add);
    await joinPair();
    a.onPeerLost(_peer(id: _bravo, port: b.boundPort));
    await flush();
    expect(a.state.peerCount, 0);
    expect(departed, isNotEmpty);
  });

  test('soft cap warns beyond 16 remotes without refusing the 17th', () async {
    await a.start(_cfg(_alpha, cs: 'ALPHA-1'));
    final remotes = <({InProcessSignalingEndpoint ep, SignalingService svc})>[];
    addTearDown(() async {
      for (final r in remotes) {
        await r.svc.dispose();
        await r.ep.close();
      }
    });

    for (var i = 0; i < 17; i++) {
      final id = 'peer-${i.toString().padLeft(2, '0')}';
      final ep = hub.endpoint();
      final svc = SignalingService(endpoint: ep, clock: clock);
      remotes.add((ep: ep, svc: svc));
      await svc.start(_cfg(id, cs: 'STN-$i'));
      a.onPeerFound(_peer(id: id, port: svc.boundPort, host: '10.0.0.$i'));
    }
    await flush();
    // Extra drains — 17 in-process handshakes.
    for (var i = 0; i < 8; i++) {
      await flush();
    }

    expect(a.state.peerCount, 17);
    expect(a.state.capWarning, isTrue);
    expect(SignalingConstants.lanPeerSoftCap, 16);
  });

  test('attachDiscovery consumes peersFound / peersLost', () async {
    final found = StreamController<DiscoveredPeer>.broadcast();
    final lost = StreamController<DiscoveredPeer>.broadcast();
    addTearDown(() async {
      await found.close();
      await lost.close();
    });

    await a.dispose();
    a = SignalingService(
      endpoint: epA,
      clock: clock,
      peersFound: found.stream,
      peersLost: lost.stream,
    );
    await a.start(_cfg(_alpha, cs: 'ALPHA-1'));
    await b.start(_cfg(_bravo, cs: 'BRAVO-7'));
    found.add(_peer(id: _bravo, port: b.boundPort));
    await flush();
    expect(a.state.peerCount, 1);
    lost.add(_peer(id: _bravo, port: b.boundPort));
    await flush();
    expect(a.state.peerCount, 0);
  });
}
