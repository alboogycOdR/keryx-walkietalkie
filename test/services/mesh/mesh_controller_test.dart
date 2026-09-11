import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/floor/transport.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/mesh/mesh_controller.dart';
import 'package:keryx/services/mesh/rtc_adapter.dart';
import 'package:keryx/services/signaling/signaling.dart';

import 'fakes/fake_rtc_adapter.dart';

const _ch = 'aabbccdd';
const _alpha = 'aaaaaaaaaa'; // lexicographically lower -> offerer
const _bravo = 'bbbbbbbbbb';

SignalingConfig _cfg(String peerId, {String cs = 'STN'}) {
  return SignalingConfig(peerId: peerId, callsign: cs, channelHashPrefix: _ch);
}

DiscoveredPeer _peer({required String id, required int port}) {
  return DiscoveredPeer(
    peerId: id,
    callsign: 'STN',
    channelHashPrefix: _ch,
    version: 1,
    host: '10.0.0.8',
    port: port,
  );
}

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

FloorEngine _soloEngine(String peerId, LoopbackHub hub, VirtualClock clock) {
  final engine = FloorEngine(
    localPeerId: peerId,
    transport: hub.attach(peerId),
    clock: clock,
  );
  engine.updateRoster({peerId});
  return engine;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MeshController — signaling handshake', () {
    late InProcessSignalingHub sigHub;
    late VirtualClock clock;
    late SignalingService sigA;
    late SignalingService sigB;
    late FakeRtcAdapter adapterA;
    late FakeRtcAdapter adapterB;
    late MeshController controllerA;
    late MeshController controllerB;

    setUp(() async {
      sigHub = InProcessSignalingHub();
      clock = VirtualClock();
      sigA = SignalingService(endpoint: sigHub.endpoint(), clock: clock);
      sigB = SignalingService(endpoint: sigHub.endpoint(), clock: clock);
      adapterA = FakeRtcAdapter();
      adapterB = FakeRtcAdapter();

      // Floor gating is not under test in this group — a single-peer
      // roster per side is enough to satisfy MeshController's dependency.
      final floorHubA = LoopbackHub();
      final floorHubB = LoopbackHub();
      controllerA = MeshController(
        localPeerId: _alpha,
        adapter: adapterA,
        signaling: sigA,
        floorEngine: _soloEngine(_alpha, floorHubA, VirtualClock()),
      );
      controllerB = MeshController(
        localPeerId: _bravo,
        adapter: adapterB,
        signaling: sigB,
        floorEngine: _soloEngine(_bravo, floorHubB, VirtualClock()),
      );

      await sigA.start(_cfg(_alpha, cs: 'ALPHA-1'));
      await sigB.start(_cfg(_bravo, cs: 'BRAVO-7'));
      sigA.onPeerFound(_peer(id: _bravo, port: sigB.boundPort));
      sigB.onPeerFound(_peer(id: _alpha, port: sigA.boundPort));
      await flush();
    });

    tearDown(() async {
      await controllerA.dispose();
      await controllerB.dispose();
      await sigA.dispose();
      await sigB.dispose();
    });

    test('lower peerId sends the offer; higher peerId waits', () async {
      expect(adapterA.connectionsCreated, hasLength(1));
      expect(
        adapterA.connectionsCreated.single.localDescription?.sdp,
        'fake-offer-sdp',
      );
    });

    test('offer/answer round-trips end to end over real signaling', () async {
      final pcA = adapterA.connectionsCreated.single;
      final pcB = adapterB.connectionsCreated.single;

      expect(pcB.remoteDescription?.sdp, 'fake-offer-sdp');
      expect(pcB.localDescription?.sdp, 'fake-answer-sdp');
      expect(pcA.remoteDescription?.sdp, 'fake-answer-sdp');
    });

    test('both sides publish the shared local track', () async {
      expect(adapterA.tracksCreated, hasLength(1));
      expect(adapterB.tracksCreated, hasLength(1));
      final pcA = adapterA.connectionsCreated.single;
      final pcB = adapterB.connectionsCreated.single;
      expect(pcA.tracksAdded, [adapterA.tracksCreated.single]);
      expect(pcB.tracksAdded, [adapterB.tracksCreated.single]);
    });

    test('the offerer opens the floor data channel', () async {
      final pcA = adapterA.connectionsCreated.single;
      expect(pcA.dataChannel, isNotNull);
      expect(pcA.dataChannel!.label, 'floor');
    });

    test('local ICE candidates relay over signaling and land as remote '
        'candidates on the other side', () async {
      final pcA = adapterA.connectionsCreated.single;
      final pcB = adapterB.connectionsCreated.single;

      pcA.onIceCandidate!(
        const RtcIceCandidate(
          candidate: 'candidate:1 1 UDP 2122260223 10.0.0.8 54321 typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      );
      await flush();

      expect(pcB.remoteCandidatesAdded, hasLength(1));
      expect(
        pcB.remoteCandidatesAdded.single.candidate,
        contains('typ host'),
      );
    });

    test('peer departure closes and removes the connection', () async {
      sigA.onPeerLost(_peer(id: _bravo, port: sigB.boundPort));
      await flush();

      expect(adapterA.connectionsCreated.single.closed, isTrue);
    });

    group('readAudioLevel (TASK-079/ADR-002 A6)', () {
      test('unavailable for a peer with no open connection', () async {
        expect(
          await controllerA.readAudioLevel('nobody'),
          const RtcUnavailableAudioLevel(),
        );
      });

      test(
        'unavailable before a remote audio track has been delivered',
        () async {
          expect(
            await controllerA.readAudioLevel(_bravo),
            const RtcUnavailableAudioLevel(),
          );
        },
      );

      test(
        'delegates to the first delivered remote audio track once present',
        () async {
          final pcA = adapterA.connectionsCreated.single;
          pcA.deliverRemoteAudioTrack(
            RtcRemoteAudioTrack(
              id: 'remote-1',
              readAudioLevel: () async => const RtcMeasuredAudioLevel(0.42),
            ),
          );

          expect(
            await controllerA.readAudioLevel(_bravo),
            const RtcMeasuredAudioLevel(0.42),
          );
        },
      );

      test('reads unavailable again after the peer departs', () async {
        final pcA = adapterA.connectionsCreated.single;
        pcA.deliverRemoteAudioTrack(
          RtcRemoteAudioTrack(
            id: 'remote-1',
            readAudioLevel: () async => const RtcMeasuredAudioLevel(0.9),
          ),
        );
        expect(
          await controllerA.readAudioLevel(_bravo),
          isA<RtcMeasuredAudioLevel>(),
        );

        sigA.onPeerLost(_peer(id: _bravo, port: sigB.boundPort));
        await flush();

        expect(
          await controllerA.readAudioLevel(_bravo),
          const RtcUnavailableAudioLevel(),
        );
      });
    });
  });

  group('MeshController — PTT gate (TS §8.5 / FR-020)', () {
    late VirtualClock clock;
    late LoopbackHub floorHub;
    late FloorEngine engine;
    late FakeRtcAdapter adapter;
    late MeshController controller;
    late InProcessSignalingHub sigHub;
    late SignalingService signaling;

    test(
      'pre-published muted on capture; grant flips enabled=true; '
      'release flips it back',
      () async {
        clock = VirtualClock();
        floorHub = LoopbackHub();
        engine = _soloEngine(_alpha, floorHub, clock);
        adapter = FakeRtcAdapter();
        sigHub = InProcessSignalingHub();
        signaling = SignalingService(endpoint: sigHub.endpoint(), clock: clock);
        await signaling.start(_cfg(_alpha));
        controller = MeshController(
          localPeerId: _alpha,
          adapter: adapter,
          signaling: signaling,
          floorEngine: engine,
        );

        // Join a peer so MeshController captures the shared local track
        // (mirrors _ensureLocalTrack() being called from _onPeerJoined).
        final other = SignalingService(
          endpoint: sigHub.endpoint(),
          clock: clock,
        );
        await other.start(_cfg(_bravo));
        signaling.onPeerFound(_peer(id: _bravo, port: other.boundPort));
        other.onPeerFound(_peer(id: _alpha, port: signaling.boundPort));
        await flush();

        expect(adapter.tracksCreated, hasLength(1));
        final track = adapter.tracksCreated.single;
        expect(track.enabled, isFalse, reason: 'pre-published muted (§8.5)');

        engine.requestTransmit();
        expect(track.enabled, isTrue, reason: 'grant -> enabled=true');

        engine.releaseTransmit();
        expect(track.enabled, isFalse, reason: 'release -> enabled=false');

        await controller.dispose();
        await other.dispose();
      },
    );

    test('TOT cut also flips the track back off', () async {
      clock = VirtualClock();
      floorHub = LoopbackHub();
      engine = _soloEngine(
        _alpha,
        floorHub,
        clock,
      );
      adapter = FakeRtcAdapter();
      sigHub = InProcessSignalingHub();
      signaling = SignalingService(endpoint: sigHub.endpoint(), clock: clock);
      await signaling.start(_cfg(_alpha));
      controller = MeshController(
        localPeerId: _alpha,
        adapter: adapter,
        signaling: signaling,
        floorEngine: engine,
      );
      final other = SignalingService(endpoint: sigHub.endpoint(), clock: clock);
      await other.start(_cfg(_bravo));
      signaling.onPeerFound(_peer(id: _bravo, port: other.boundPort));
      other.onPeerFound(_peer(id: _alpha, port: signaling.boundPort));
      await flush();

      engine.tot = FloorEngine.minTot;
      engine.requestTransmit();
      final track = adapter.tracksCreated.single;
      expect(track.enabled, isTrue);

      clock.elapse(FloorEngine.minTot);

      expect(track.enabled, isFalse, reason: 'TOT cut dispatches EndTransmit');

      await controller.dispose();
      await other.dispose();
    });
  });
}
