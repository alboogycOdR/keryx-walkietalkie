import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/services/mesh/floor_data_channel_transport.dart';
import 'package:keryx/services/mesh/mesh_connection.dart';
import 'package:keryx/services/mesh/rtc_adapter.dart';

import 'fakes/fake_rtc_adapter.dart';

const _probe = TxStart(peer: 'probe');

void main() {
  group('MeshConnection', () {
    late FakeLocalAudioTrack track;
    late MeshFloorTransport transport;

    setUp(() {
      track = FakeLocalAudioTrack();
      transport = MeshFloorTransport();
    });

    tearDown(() => transport.dispose());

    test(
      'offerer: publishes the shared track muted, opens the floor data '
      'channel, sets local description',
      () async {
        final pc = FakePeerConnection();
        final conn = MeshConnection(
          peerId: 'bravo',
          pc: pc,
          localTrack: track,
          floorTransport: transport,
          onLocalIceCandidate: (_) {},
        );

        expect(track.enabled, isFalse, reason: 'pre-published muted (§8.5)');

        final offer = await conn.createOffer();

        expect(pc.tracksAdded, [track]);
        expect(track.enabled, isFalse, reason: 'createOffer must not enable');
        expect(pc.dataChannel, isNotNull);
        expect(pc.dataChannel!.label, 'floor');
        expect(pc.localDescription, isNotNull);
        expect(offer.type, 'offer');
      },
    );

    test('offerer registers the data channel with the floor transport', () async {
      final pc = FakePeerConnection();
      final conn = MeshConnection(
        peerId: 'bravo',
        pc: pc,
        localTrack: track,
        floorTransport: transport,
        onLocalIceCandidate: (_) {},
      );
      await conn.createOffer();

      transport.send(_probe);
      // Attached channel should have received the fan-out send.
      expect(pc.dataChannel!.sent, hasLength(1));
    });

    test(
      'answerer: publishes the shared track, applies remote offer, '
      'returns local answer',
      () async {
        final pc = FakePeerConnection();
        final conn = MeshConnection(
          peerId: 'alpha',
          pc: pc,
          localTrack: track,
          floorTransport: transport,
          onLocalIceCandidate: (_) {},
        );

        final answer = await conn.createAnswer(
          const RtcSessionDescription(sdp: 'remote-offer-sdp', type: 'offer'),
        );

        expect(pc.tracksAdded, [track]);
        expect(pc.remoteDescription!.sdp, 'remote-offer-sdp');
        expect(pc.localDescription, isNotNull);
        expect(answer.type, 'answer');
      },
    );

    test('answerer receives the floor channel via onDataChannel', () async {
      final pc = FakePeerConnection();
      final conn = MeshConnection(
        peerId: 'alpha',
        pc: pc,
        localTrack: track,
        floorTransport: transport,
        onLocalIceCandidate: (_) {},
      );
      await conn.createAnswer(
        const RtcSessionDescription(sdp: 'x', type: 'offer'),
      );

      final inbound = FakeDataChannel(label: 'floor');
      pc.simulateRemoteDataChannel(inbound);

      transport.send(_probe);
      expect(inbound.sent, hasLength(1));
    });

    test('forwards local ICE candidates to the caller-supplied callback', () {
      final pc = FakePeerConnection();
      final captured = <RtcIceCandidate>[];
      MeshConnection(
        peerId: 'bravo',
        pc: pc,
        localTrack: track,
        floorTransport: transport,
        onLocalIceCandidate: captured.add,
      );

      pc.onIceCandidate!(
        const RtcIceCandidate(candidate: 'candidate:1 ...', sdpMid: '0'),
      );

      expect(captured, hasLength(1));
      expect(captured.single.candidate, 'candidate:1 ...');
    });

    test('close() detaches from the floor transport and closes the pc', () async {
      final pc = FakePeerConnection();
      final conn = MeshConnection(
        peerId: 'bravo',
        pc: pc,
        localTrack: track,
        floorTransport: transport,
        onLocalIceCandidate: (_) {},
      );
      await conn.createOffer();

      await conn.close();

      expect(pc.closed, isTrue);
      transport.send(_probe);
      expect(pc.dataChannel!.sent, isEmpty, reason: 'detached, no fan-out');
    });
  });
}
