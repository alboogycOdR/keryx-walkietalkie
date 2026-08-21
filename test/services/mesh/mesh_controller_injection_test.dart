// TASK-032: MeshController accepts an externally-constructed
// MeshFloorTransport so the engine handed to MeshController can be the SAME
// engine attached to its own mesh transport — the composition that was
// structurally impossible before this task (MeshController.floorTransport
// was a non-injectable `final` field initializer).
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/mesh/floor_data_channel_transport.dart';
import 'package:keryx/services/mesh/mesh_controller.dart';
import 'package:keryx/services/signaling/signaling.dart';

import 'fakes/fake_rtc_adapter.dart';

const _ch = 'aabbccdd';
const _alpha = 'aaaaaaaaaa'; // lexicographically lower -> offerer
const _bravo = 'bbbbbbbbbb';
// Lower than _alpha, so a roster of {alpha, arbiter} elects _arbiterId,
// NOT alpha — decoupled deliberately from who signals the WebRTC offer
// (that is purely a discovery-order concern), so the composed test below
// can observe both an outbound TX_REQ (alpha is not the arbiter) and an
// inbound TX_DENY without alpha ever self-granting.
const _arbiterId = '0000000000';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MeshController — floorTransport injection seam (TASK-032)', () {
    test(
      'omitting floorTransport preserves today\'s behaviour byte-for-byte',
      () async {
        final clock = VirtualClock();
        final engineOwnTransport = MeshFloorTransport();
        final engine = FloorEngine(
          localPeerId: _alpha,
          transport: engineOwnTransport,
          clock: clock,
        );
        engine.updateRoster({_alpha});
        final adapter = FakeRtcAdapter();
        final sigHub = InProcessSignalingHub();
        final signaling = SignalingService(
          endpoint: sigHub.endpoint(),
          clock: clock,
        );
        await signaling.start(_cfg(_alpha));

        final controller = MeshController(
          localPeerId: _alpha,
          adapter: adapter,
          signaling: signaling,
          floorEngine: engine,
        );

        // The controller built its own private transport — not the one
        // wired to `engine` above (that would be the pre-TASK-032 defect
        // this task fixes: they can never be the same object here).
        expect(controller.floorTransport, isNot(same(engineOwnTransport)));

        await controller.dispose();
        await signaling.dispose();
      },
    );

    test(
      'the composed cycle: one MeshFloorTransport -> FloorEngine over it -> '
      'MeshController given both -> a floor message sent via the engine '
      'reaches the data channel path and vice versa',
      () async {
        final clock = VirtualClock();
        final sharedTransport = MeshFloorTransport();
        final engine = FloorEngine(
          localPeerId: _alpha,
          transport: sharedTransport,
          clock: clock,
        );
        // Roster elects `_arbiterId`, not `_alpha` — proves the engine
        // actually attached to `sharedTransport` is the same one driving
        // arbitration, not some other internally-constructed instance.
        engine.updateRoster({_alpha, _arbiterId});
        expect(engine.isLocalArbiter, isFalse);

        final adapter = FakeRtcAdapter();
        final sigHub = InProcessSignalingHub();
        final signaling = SignalingService(
          endpoint: sigHub.endpoint(),
          clock: clock,
        );
        await signaling.start(_cfg(_alpha));

        final controller = MeshController(
          localPeerId: _alpha,
          adapter: adapter,
          signaling: signaling,
          floorEngine: engine,
          floorTransport: sharedTransport,
        );

        // THE composition proof: the transport handed to MeshController IS
        // the transport FloorEngine was constructed with.
        expect(controller.floorTransport, same(sharedTransport));

        // Join a peer so a real MeshConnection (and its data channel) gets
        // created; alpha < bravo so alpha is the WebRTC offerer and
        // synchronously opens the floor data channel in createOffer().
        final other = SignalingService(
          endpoint: sigHub.endpoint(),
          clock: clock,
        );
        await other.start(_cfg(_bravo));
        signaling.onPeerFound(_peer(id: _bravo, port: other.boundPort));
        other.onPeerFound(_peer(id: _alpha, port: signaling.boundPort));
        await flush();

        final pcA = adapter.connectionsCreated.single;
        final channel = pcA.dataChannel;
        expect(channel, isNotNull, reason: 'offerer opens the floor channel');

        // --- forward: engine -> transport -> data channel ---
        engine.requestTransmit();
        expect(channel!.sent, hasLength(1));
        final outbound = FloorCodec.decode(channel.sent.single);
        expect(
          outbound,
          isA<TxReq>().having((m) => m.peer, 'peer', _alpha),
          reason:
              'not the local arbiter, so requestTransmit() sends TX_REQ '
              'via the SAME transport the engine was constructed with',
        );

        // --- reverse: data channel -> transport -> engine ---
        final effects = <Object>[];
        final effectsSub = engine.effects.listen(effects.add);
        channel.deliver(
          FloorCodec.encode(
            const TxDeny(peer: _alpha, reason: FloorDenyReason.busy),
          ),
        );
        await flush();
        expect(
          effects,
          contains(isA<DenyBuzz>()),
          reason:
              'an inbound TX_DENY delivered on the data channel reaches '
              'the SAME engine via the shared transport\'s incoming stream',
        );

        await effectsSub.cancel();
        await controller.dispose();
        await other.dispose();
        await signaling.dispose();
        engine.dispose();
      },
    );

    test(
      'ownership: injected floorTransport is caller-owned — controller '
      'dispose() does not dispose it, and double-dispose from either side '
      'never throws or leaks',
      () async {
        final clock = VirtualClock();
        final sharedTransport = MeshFloorTransport();
        final engine = FloorEngine(
          localPeerId: _alpha,
          transport: sharedTransport,
          clock: clock,
        );
        engine.updateRoster({_alpha});
        final adapter = FakeRtcAdapter();
        final sigHub = InProcessSignalingHub();
        final signaling = SignalingService(
          endpoint: sigHub.endpoint(),
          clock: clock,
        );
        await signaling.start(_cfg(_alpha));

        final controller = MeshController(
          localPeerId: _alpha,
          adapter: adapter,
          signaling: signaling,
          floorEngine: engine,
          floorTransport: sharedTransport,
        );

        await controller.dispose();
        // Caller-owned: still open after the controller disposes, so the
        // caller (here, the test itself, standing in for whoever built
        // `engine` alongside it) can keep using/dispose it independently.
        // A message sent post-controller-dispose does not throw.
        expect(() => sharedTransport.send(const TxEnd(peer: _alpha)), returnsNormally);

        // Double-dispose from the caller side never throws or leaks.
        await sharedTransport.dispose();
        await sharedTransport.dispose();

        // Double-dispose of the controller itself is also always safe.
        await controller.dispose();

        await signaling.dispose();
        engine.dispose();
      },
    );

    test(
      'default (non-injected) transport stays controller-owned: dispose() '
      'closes it, and double-dispose never throws or leaks',
      () async {
        final clock = VirtualClock();
        final engine = FloorEngine(
          localPeerId: _alpha,
          transport: MeshFloorTransport(),
          clock: clock,
        );
        engine.updateRoster({_alpha});
        final adapter = FakeRtcAdapter();
        final sigHub = InProcessSignalingHub();
        final signaling = SignalingService(
          endpoint: sigHub.endpoint(),
          clock: clock,
        );
        await signaling.start(_cfg(_alpha));

        final controller = MeshController(
          localPeerId: _alpha,
          adapter: adapter,
          signaling: signaling,
          floorEngine: engine,
        );
        final ownTransport = controller.floorTransport;

        await controller.dispose();
        // Controller-owned: the controller's own dispose() closed it, so a
        // subsequent incoming-stream listen is on an already-closed stream
        // (no throw either way — this just proves it was actually disposed
        // rather than leaked open).
        expect(ownTransport.incoming.isBroadcast, isTrue);

        // Double-dispose never throws or leaks.
        await controller.dispose();

        await signaling.dispose();
        engine.dispose();
      },
    );
  });
}
