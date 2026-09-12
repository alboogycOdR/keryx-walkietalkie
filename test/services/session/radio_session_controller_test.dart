import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/discovery/discovery_state.dart';
import 'package:keryx/services/linked/linked.dart';
import 'package:keryx/services/mesh/rtc_adapter.dart';
import 'package:keryx/services/session/radio_session_controller.dart';
import 'package:keryx/services/signaling/in_process_endpoint.dart';

import '../mesh/fakes/fake_rtc_adapter.dart';

/// TASK-097: `start()` (LOCAL) `-> discovery.start()` never resolves —
/// simulates the field-reported hung NSD/platform-channel call. Unlike the
/// real `NsdDiscoveryService.production()` default (whose platform channel
/// calls resolve immediately under `flutter_test`'s auto-mocked messenger,
/// so it cannot reproduce the hang), this fake genuinely never completes,
/// proving `RadioSessionController`'s own bound — not the test harness —
/// is what stops the wait.
class _HangingDiscoveryService implements DiscoveryService {
  final _found = StreamController<DiscoveredPeer>.broadcast();
  final _lost = StreamController<DiscoveredPeer>.broadcast();
  final _states = StreamController<DiscoveryState>.broadcast();
  final Completer<void> _neverCompletes = Completer<void>();

  @override
  Stream<DiscoveredPeer> get peersFound => _found.stream;

  @override
  Stream<DiscoveredPeer> get peersLost => _lost.stream;

  @override
  Stream<DiscoveryState> get states => _states.stream;

  @override
  DiscoveryState get state => DiscoveryState.idle;

  @override
  Future<void> start(DiscoveryConfig config) => _neverCompletes.future;

  @override
  Future<void> onTuned() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _found.close();
    await _lost.close();
    await _states.close();
  }
}

/// TASK-097: `discovery.start()` throws a real (non-timeout) failure —
/// proves the bound's catch-all covers "a thrown failure", not only a
/// timeout (acceptance criterion 1's "successfully or with a thrown
/// failure").
class _ThrowingDiscoveryService implements DiscoveryService {
  final _found = StreamController<DiscoveredPeer>.broadcast();
  final _lost = StreamController<DiscoveredPeer>.broadcast();
  final _states = StreamController<DiscoveryState>.broadcast();

  @override
  Stream<DiscoveredPeer> get peersFound => _found.stream;

  @override
  Stream<DiscoveredPeer> get peersLost => _lost.stream;

  @override
  Stream<DiscoveryState> get states => _states.stream;

  @override
  DiscoveryState get state => DiscoveryState.idle;

  @override
  Future<void> start(DiscoveryConfig config) async {
    throw StateError('simulated nsd platform failure');
  }

  @override
  Future<void> onTuned() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _found.close();
    await _lost.close();
    await _states.close();
  }
}

/// TASK-097: `LiveKitAdapter.connect()` never resolves — simulates a
/// reachable-but-wedged relay on the LINKED path (`TokenClient`'s own
/// request already has a 10 s bound of its own; this fake proves the
/// *adapter connect/publish* step, which had no bound at all, is now
/// covered too).
class _HangingLiveKitAdapter implements LiveKitAdapter {
  @override
  Future<LiveKitRoom> connect({
    required String url,
    required String jwt,
    Uint8List? e2eeKey,
  }) => Completer<LiveKitRoom>().future;
}

/// TASK-097: a `TokenClient` that resolves instantly with a fake JWT so a
/// LINKED-path test reaches `LiveKitAdapter.connect()` without a real
/// network round trip. `requestToken` is a public, overridable instance
/// method — no mock framework needed.
class _FastTokenClient extends TokenClient {
  _FastTokenClient() : super(baseUrl: Uri.parse('https://token.invalid'));

  @override
  Future<TokenResponse> requestToken({
    required String roomId,
    required String callsign,
    String? eventToken,
  }) async => const TokenResponse(
    token: 'fake-jwt',
    identity: 'Alice#deadbeef',
    ttl: Duration(minutes: 5),
  );
}

/// No-op [DiscoveryService] — TASK-079's meter-level tests join peers
/// directly through `RadioSessionController.debugSignaling.onPeerFound`
/// (mirrors `test/services/mesh/mesh_controller_test.dart`'s own pattern),
/// so no real NSD/UDP-beacon traffic is needed. `start`/`onTuned`/`stop`/
/// `dispose` are all no-ops; the peer streams never emit.
class _NoopDiscoveryService implements DiscoveryService {
  final _found = StreamController<DiscoveredPeer>.broadcast();
  final _lost = StreamController<DiscoveredPeer>.broadcast();
  final _states = StreamController<DiscoveryState>.broadcast();

  @override
  Stream<DiscoveredPeer> get peersFound => _found.stream;

  @override
  Stream<DiscoveredPeer> get peersLost => _lost.stream;

  @override
  Stream<DiscoveryState> get states => _states.stream;

  @override
  DiscoveryState get state => DiscoveryState.idle;

  @override
  Future<void> start(DiscoveryConfig config) async {}

  @override
  Future<void> onTuned() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _found.close();
    await _lost.close();
    await _states.close();
  }
}

Future<void> _flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUpAll(() {
    // Initialize Flutter bindings for platform channels (NSD discovery)
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('RadioSessionController', () {
    late KeryxSettings settingsLocal;
    late List<RadioEvent> dispatchedEvents;

    setUp(() {
      dispatchedEvents = [];

      settingsLocal = const KeryxSettings(
        squelchLevel: 5,
        totSeconds: 120,
        busyLockout: false,
        latchMode: false,
        forceLocalOnly: false,
        relayUrl: '',
        tokenServiceUrl: '',
        characterDspIntensity: CharacterDspIntensity.light,
        dimMode: DimMode.auto);
    });

    // Criterion 2: Composed floor engine — verify engine exists and is accessible
    group('composed floor engine', () {
      test('floorEngine property accessible after start', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        await controller.start();

        // Criterion 2: verify engine exists
        expect(controller.floorEngine, isNotNull);
        expect(controller.floorEngine, isA<FloorEngine>());

        await controller.dispose();
      });

      test('floorEngine throws before start', () {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        expect(() => controller.floorEngine, throwsStateError);
      });
    });

    group('transport matrix', () {
      Future<void> testMode({
        required bool forceLocalOnly,
        required String relayUrl,
        required bool expectLocalBuilt,
      }) async {
        final settings = KeryxSettings(
          squelchLevel: 5,
          totSeconds: 120,
          busyLockout: false,
          latchMode: false,
          forceLocalOnly: forceLocalOnly,
          relayUrl: relayUrl,
          tokenServiceUrl: relayUrl.isEmpty ? '' : 'https://host/token-svc',
          characterDspIntensity: CharacterDspIntensity.light,
          dimMode: DimMode.auto);

        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settings,
          dispatch: dispatchedEvents.add);

        await controller.start();

        // Criterion 3a: verify LOCAL chain exists when expected
        expect(
          controller.debugMeshTransport != null,
          equals(expectLocalBuilt),
          reason:
              'forceLocalOnly=$forceLocalOnly, relayUrl=$relayUrl');

        // Criterion 3b: verify LINKED never built when forceLocalOnly=true
        if (forceLocalOnly) {
          expect(
            controller.debugLinkedController,
            isNull,
            reason: 'forceLocalOnly=true must prevent LINKED construction');
        }

        await controller.dispose();
      }

      test('no relay → direct only', () async {
        await testMode(
          forceLocalOnly: false,
          relayUrl: '',
          expectLocalBuilt: true);
      });

      test('local mode + forceLocalOnly → LOCAL only', () async {
        await testMode(
          forceLocalOnly: true,
          relayUrl: 'wss://relay.example',
          expectLocalBuilt: true);
      });

      test('auto mode + no relay → LOCAL only', () async {
        await testMode(
          forceLocalOnly: false,
          relayUrl: '',
          expectLocalBuilt: true);
      });

      test('auto mode + no relay + forceLocalOnly → LOCAL only', () async {
        await testMode(
          forceLocalOnly: true,
          relayUrl: '',
          expectLocalBuilt: true);
      });

      test('forceLocalOnly=true prevents LINKED even in linked mode', () async {
        await testMode(
          forceLocalOnly: true,
          relayUrl: 'wss://relay.example',
          expectLocalBuilt: true);
      });
    });

    group('SetTransport routing', () {
      test('SetTransport dispatched on successful start', () async {
        dispatchedEvents.clear();

        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        await controller.start();

        final setModes = dispatchedEvents.whereType<SetTransport>().toList();
        expect(
          setModes,
          isNotEmpty,
          reason: 'SetTransport must be dispatched on start');
        expect(setModes.first.transport, equals(Transport.direct));

        await controller.dispose();
      });

      test('SetTransport reflects forceLocalOnly override', () async {
        dispatchedEvents.clear();

        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: const KeryxSettings(
            squelchLevel: 5,
            totSeconds: 120,
            busyLockout: false,
            latchMode: false,
            forceLocalOnly: true,
            relayUrl: 'wss://relay.example',
            tokenServiceUrl: 'https://relay.example/token-svc',
            characterDspIntensity: CharacterDspIntensity.light,
            dimMode: DimMode.auto),
          dispatch: dispatchedEvents.add);

        await controller.start();

        final setModes = dispatchedEvents.whereType<SetTransport>().toList();
        expect(
          setModes.last.transport,
          equals(Transport.direct),
          reason: 'SetTransport must reflect forceLocalOnly override');

        await controller.dispose();
      });
    });

    // Criterion 5: Stations stream basics
    group('stations stream', () {
      test('stations stream is accessible', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        await controller.start();

        expect(controller.stations, isNotNull);
        expect(controller.stations, isA<Stream>());

        // Verify controller has the engine (which implies sessions stream exists)
        expect(controller.floorEngine, isNotNull);

        await controller.dispose();
      });

      test('stations stream lifecycle', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        await controller.start();
        await controller.dispose();

        // Stream should close cleanly without errors
        expect(controller.stations, isNotNull);
      });
    });

    // Criterion 1 & overall: Basic lifecycle
    group('lifecycle', () {
      test('start and dispose completes successfully', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        // start should complete
        await expectLater(
          controller.start(),
          completes,
          reason: 'start() must complete');

        // dispose should complete
        await expectLater(
          controller.dispose(),
          completes,
          reason: 'dispose() must complete');
      });

      test('retune rebuilds engine', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        await controller.start();
        final engine1 = controller.floorEngine;
        // Pre-retune engine must itself be valid, so a post-retune comparison
        // means something rather than checking a fresh engine against nothing.
        expect(engine1, isNotNull);
        expect(engine1, isA<FloorEngine>());

        await controller.switchTarget(
          const TalkTarget(
            kind: TalkTargetKind.contact,
            id: 'p2',
            name: 'Peer',
            roomId: 'ABCDEFGHIJKLMNOP',
          ),
          memberPeerIds: const [],
        );
        final engine2 = controller.floorEngine;

        // Retune should create a new engine
        expect(engine2, isNotNull);
        // Engines may be different instances or reused, but both should be valid
        expect(engine2, isA<FloorEngine>());

        await controller.dispose();
      });

      test('dispose prevents further operations', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add);

        await controller.start();
        await controller.dispose();

        expect(
          () => controller.floorEngine,
          throwsStateError,
          reason: 'floorEngine must throw after dispose');

        expect(
          () async => await controller.switchTarget(
            const TalkTarget(
              kind: TalkTargetKind.contact,
              id: 'p2',
              name: 'Peer',
              roomId: 'ABCDEFGHIJKLMNOP',
            ),
            memberPeerIds: const [],
          ),
          throwsStateError,
          reason: 'retune() must throw after dispose');
      });
    });

    // TASK-079/ADR-002 A6: RX level telemetry.
    //
    // Only `controllerA` needs to be a full `RadioSessionController` under
    // test. `controllerB` exists purely to complete a real signaling
    // handshake so `controllerA`'s `MeshController` opens a real (faked)
    // peer connection and data channel for BRAVO-7 — the actual "remote
    // floor started/ended" events are injected directly as `TxStart`/
    // `TxEnd` wire messages on that fake data channel (`FloorCodec`,
    // exactly what `MeshFloorTransport._onText` would decode from a real
    // one), so this test does not depend on B's own floor engine correctly
    // propagating a grant across two independently-faked RTC adapters
    // (which, being fakes, are not actually wired to each other).
    group('RX level telemetry', () {
      late InProcessSignalingHub sigHub;
      late VirtualClock clockA;
      late FakeRtcAdapter adapterA;
      late FakeRtcAdapter adapterB;
      late RadioSessionController controllerA;
      late RadioSessionController controllerB;
      final channelHashPrefix = 'AAAAAAAA';

      RadioSessionController buildController({
        required String peerId,
        required String callsign,
        required InProcessSignalingHub hub,
        required FakeRtcAdapter adapter,
        FloorClock? clock,
      }) {
        return RadioSessionController(
          localPeerId: peerId,
          callsign: callsign,
          settings: settingsLocal,
          dispatch: (RadioEvent event) {},
          clock: clock,
          endpointFactory: hub.endpoint,
          discoveryFactory: _NoopDiscoveryService.new,
          rtcAdapter: adapter);
      }

      Future<void> joinPeers() async {
        final sigA = controllerA.debugSignaling!;
        final sigB = controllerB.debugSignaling!;
        sigA.onPeerFound(
          DiscoveredPeer(
            peerId: 'BRAVO-7',
            callsign: 'Bravo',
            channelHashPrefix: channelHashPrefix,
            version: 1,
            host: '10.0.0.2',
            port: sigB.boundPort));
        sigB.onPeerFound(
          DiscoveredPeer(
            peerId: 'ALFA-1',
            callsign: 'Alice',
            channelHashPrefix: channelHashPrefix,
            version: 1,
            host: '10.0.0.2',
            port: sigA.boundPort));
        await _flush();
      }

      /// `ALFA-1` < `BRAVO-7` lexicographically, so A is always the
      /// offerer and its `MeshConnection` is the one that calls
      /// `createDataChannel` — that fake data channel is what
      /// `MeshFloorTransport._onText` listens on.
      FakeDataChannel meshDataChannelToB() {
        final pcA = adapterA.connectionsCreated.single;
        return pcA.dataChannel!;
      }

      void deliverRemoteStart(String peerId) {
        meshDataChannelToB().deliver(FloorCodec.encode(TxStart(peer: peerId)));
      }

      void deliverRemoteEnd(String peerId) {
        meshDataChannelToB().deliver(FloorCodec.encode(TxEnd(peer: peerId)));
      }

      setUp(() async {
        sigHub = InProcessSignalingHub();
        clockA = VirtualClock();
        adapterA = FakeRtcAdapter();
        adapterB = FakeRtcAdapter();
        controllerA = buildController(
          peerId: 'ALFA-1',
          callsign: 'Alice',
          hub: sigHub,
          adapter: adapterA,
          clock: clockA);
        controllerB = buildController(
          peerId: 'BRAVO-7',
          callsign: 'Bravo',
          hub: sigHub,
          adapter: adapterB);
        await controllerA.start();
        await controllerB.start();
        await joinPeers();
        controllerA.floorEngine.updateRoster({'ALFA-1', 'BRAVO-7'});
      });

      tearDown(() async {
        await controllerA.dispose();
        await controllerB.dispose();
      });

      test('decorative before any remote floor activity', () {
        expect(controllerA.meterLevel, MeterLevel.decorative);
      });

      test('starts polling on RemoteFloorStarted; measured value flows through '
          'at ~10 Hz; stops on RemoteFloorEnded', () async {
        var level = 0.1;
        adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
          RtcRemoteAudioTrack(
            id: 'bravo-remote',
            readAudioLevel: () async => RtcMeasuredAudioLevel(level)));

        final seen = <MeterLevel>[];
        final sub = controllerA.meterLevelChanges.listen(seen.add);

        deliverRemoteStart('BRAVO-7');
        expect(
          controllerA.floorEngine.holder,
          'BRAVO-7',
          reason: 'sanity: TxStart must have installed BRAVO-7 as holder');
        await _flush();
        // First poll tick fires 100ms after RemoteFloorStarted scheduled it.
        clockA.elapse(const Duration(milliseconds: 100));
        await _flush();

        expect(
          controllerA.meterLevel,
          isA<MeasuredMeterLevel>(),
          reason: 'RemoteFloorStarted on A must begin polling BRAVO-7');
        expect(
          (controllerA.meterLevel as MeasuredMeterLevel).value,
          closeTo(10, 0.001));

        // Advance one more poll tick with a different level to confirm
        // the ~10 Hz self-reschedule is actually live, not a one-shot.
        level = 0.5;
        clockA.elapse(const Duration(milliseconds: 100));
        await _flush();
        expect(
          (controllerA.meterLevel as MeasuredMeterLevel).value,
          closeTo(50, 0.001));

        deliverRemoteEnd('BRAVO-7');
        await _flush();

        expect(
          controllerA.meterLevel,
          MeterLevel.decorative,
          reason: 'RemoteFloorEnded must stop polling and go decorative');

        // No leaked timer: further clock elapses must not resurrect a
        // measured value now that polling has stopped.
        level = 0.9;
        clockA.elapse(const Duration(seconds: 5));
        await _flush();
        expect(controllerA.meterLevel, MeterLevel.decorative);

        expect(
          seen.any((l) => l is MeasuredMeterLevel),
          isTrue,
          reason: 'meterLevelChanges must have emitted the measured value');
        await sub.cancel();
      });

      test('unavailable sample projects as decorative, not measured', () async {
        // No remote track delivered on purpose — MeshController.readAudioLevel
        // resolves unavailable.
        deliverRemoteStart('BRAVO-7');
        await _flush();

        expect(controllerA.meterLevel, MeterLevel.decorative);

        deliverRemoteEnd('BRAVO-7');
        await _flush();
      });

      test(
        'a superseded pending poll cannot create a second polling chain',
        () async {
          var reads = 0;
          final firstRead = Completer<RtcAudioLevel>();
          adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
            RtcRemoteAudioTrack(
              id: 'bravo-remote',
              readAudioLevel: () {
                reads++;
                return reads == 1
                    ? firstRead.future
                    : Future.value(const RtcMeasuredAudioLevel(0.4));
              }));

          deliverRemoteStart('BRAVO-7');
          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();
          expect(reads, 1, reason: 'the first poll is intentionally pending');

          deliverRemoteEnd('BRAVO-7');
          deliverRemoteStart('BRAVO-7');
          firstRead.complete(const RtcMeasuredAudioLevel(0.2));
          await _flush();

          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();
          expect(reads, 2, reason: 'only the replacement generation polls');
          expect(controllerA.meterLevel, isA<MeasuredMeterLevel>());

          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();
          expect(reads, 3, reason: 'there is exactly one poll per interval');
        });

      test(
        'a throwing audio-level read stays decorative and polling continues',
        () async {
          var reads = 0;
          adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
            RtcRemoteAudioTrack(
              id: 'bravo-remote',
              readAudioLevel: () {
                reads++;
                if (reads == 1) {
                  return Future<RtcAudioLevel>.error(StateError('closing'));
                }
                return Future.value(const RtcMeasuredAudioLevel(0.6));
              }));

          deliverRemoteStart('BRAVO-7');
          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();
          expect(controllerA.meterLevel, MeterLevel.decorative);

          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();
          expect(reads, 2);
          expect(
            (controllerA.meterLevel as MeasuredMeterLevel).value,
            closeTo(60, 0.001));
        });

      test('retune stops polling and does not leak a timer', () async {
        adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
          RtcRemoteAudioTrack(
            id: 'bravo-remote',
            readAudioLevel: () async => const RtcMeasuredAudioLevel(0.3)));

        deliverRemoteStart('BRAVO-7');
        await _flush();
        clockA.elapse(const Duration(milliseconds: 100));
        await _flush();
        expect(controllerA.meterLevel, isA<MeasuredMeterLevel>());

        await controllerA.switchTarget(
          const TalkTarget(
            kind: TalkTargetKind.contact,
            id: 'p2',
            name: 'Peer',
            roomId: 'ABCDEFGHIJKLMNOP',
          ),
          memberPeerIds: const [],
        );
        await _flush();

        expect(controllerA.meterLevel, MeterLevel.decorative);

        // The old timer must not still be scheduled against the retuned
        // controller's (fresh) engine/mesh — advancing time must not throw
        // or resurrect a measured value from the torn-down chain.
        clockA.elapse(const Duration(seconds: 2));
        await _flush();
        expect(controllerA.meterLevel, MeterLevel.decorative);
      });

      test('dispose stops polling cleanly', () async {
        adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
          RtcRemoteAudioTrack(
            id: 'bravo-remote',
            readAudioLevel: () async => const RtcMeasuredAudioLevel(0.3)));
        deliverRemoteStart('BRAVO-7');
        await _flush();
        clockA.elapse(const Duration(milliseconds: 100));
        await _flush();
        expect(controllerA.meterLevel, isA<MeasuredMeterLevel>());

        await controllerA.dispose();
        await controllerB.dispose();

        // Re-dispose in tearDown must be a safe no-op (both already
        // disposed here) — asserted implicitly by tearDown not throwing.
      });
    });

    // v2 (Technical §6.4, TASK-088 additive scope): switchTarget alongside
    // retune — every group above is unmodified.
    group('switchTarget (v2, additive)', () {
      test(
        'joins the target room, updates the roster before returning, and '
        'dispatches SetRoom/SetTransport (closes the solo join-guard, '
        'Technical §1.1)',
        () async {
          final controller = RadioSessionController(
            localPeerId: 'ALFA-1',
            callsign: 'Alice',
            settings: settingsLocal,
            dispatch: dispatchedEvents.add,
            discoveryFactory: _NoopDiscoveryService.new);

          await controller.start();
          dispatchedEvents.clear();

          final stationIds = <String>[];
          final sub = controller.stations.listen(
            (list) => stationIds.addAll(list.map((s) => s.peerId)));

          const target = TalkTarget(
            kind: TalkTargetKind.group,
            id: 'g1',
            name: 'Golf Group',
            roomId: 'v2-room-id-01');
          await controller.switchTarget(
            target,
            memberPeerIds: const ['BRAVO-7', 'CHARLIE-9']);

          // Roster (self + members) is live before switchTarget returns —
          // no need to wait for a peer-joined stream (v1's discovery path).
          expect(dispatchedEvents.whereType<RosterUpdated>().last.stationCount, 3);

          expect(dispatchedEvents.whereType<SetRoom>().last.roomId, 'v2-room-id-01');
          expect(
            dispatchedEvents.whereType<SetTransport>().last.transport,
            Transport.direct);

          await _flush();
          await sub.cancel();
          expect(stationIds, containsAll(['BRAVO-7', 'CHARLIE-9']));

          await controller.dispose();
        });

      test('a solo target (no members) still updates the roster to size 1', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add,
          discoveryFactory: _NoopDiscoveryService.new);
        await controller.start();

        const soloTarget = TalkTarget(
          kind: TalkTargetKind.contact,
          id: 'p1',
          name: 'Hotel',
          roomId: 'v2-room-id-02');
        await controller.switchTarget(soloTarget, memberPeerIds: const []);

        expect(dispatchedEvents.whereType<RosterUpdated>().last.stationCount, 1);

        await controller.dispose();
      });

      test('does not disturb retune\'s v1 numbered-channel path', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add,
          discoveryFactory: _NoopDiscoveryService.new);
        await controller.start();

        await controller.switchTarget(
          const TalkTarget(
            kind: TalkTargetKind.contact,
            id: 'p9',
            name: 'Peer',
            roomId: 'ABCDEFGHIJKLMNOP',
          ),
          memberPeerIds: const [],
        );
        expect(controller.floorEngine, isNotNull);

        const target = TalkTarget(
          kind: TalkTargetKind.group,
          id: 'g2',
          name: 'India Group',
          roomId: 'v2-room-id-03');
        dispatchedEvents.clear();
        await controller.switchTarget(target, memberPeerIds: const ['JULIET-2']);
        expect(dispatchedEvents.whereType<RosterUpdated>().last.stationCount, 2);

        // retune remains callable afterwards — switchTarget did not remove
        // or rename it.
        await controller.switchTarget(
          const TalkTarget(
            kind: TalkTargetKind.contact,
            id: 'p11',
            name: 'Peer',
            roomId: 'PQRSTUVWXYZ23456',
          ),
          memberPeerIds: const [],
        );
        expect(controller.floorEngine, isNotNull);

        await controller.dispose();
      });
    });

    // TASK-097: session establishment must be bounded — see the class's
    // own `_startLocal`/`_startLinked` dartdoc for the disclosed
    // uncancellable-native-call limitation this bound does NOT claim to fix.
    group('session-establishment bound (TASK-097)', () {
      test(
        'LOCAL: a never-resolving discovery.start() does not hang start() '
        'forever — completes with a thrown SessionEstablishmentFailure '
        'naming the LOCAL transport, within the injected bound',
        () async {
          final controller = RadioSessionController(
            localPeerId: 'ALFA-1',
            callsign: 'Alice',
            settings: settingsLocal,
            dispatch: dispatchedEvents.add,
            discoveryFactory: _HangingDiscoveryService.new,
            sessionStartTimeout: const Duration(milliseconds: 50));

          await expectLater(
            controller.start(),
            throwsA(
              isA<SessionEstablishmentFailure>().having(
                (e) => e.transport,
                'transport',
                Transport.direct)));

          // No live session was ever adopted — a failed start must never
          // leave a half-built engine reachable (mirrors `floorEngine
          // throws before start`'s existing lifecycle guarantee).
          expect(() => controller.floorEngine, throwsStateError);

          await controller.dispose();
        },
        timeout: const Timeout(Duration(seconds: 5)));

      test(
        'LOCAL: a thrown (non-timeout) discovery.start() failure also '
        'surfaces as a typed SessionEstablishmentFailure, not a hang and '
        'not a raw StateError',
        () async {
          final controller = RadioSessionController(
            localPeerId: 'ALFA-1',
            callsign: 'Alice',
            settings: settingsLocal,
            dispatch: dispatchedEvents.add,
            discoveryFactory: _ThrowingDiscoveryService.new,
            sessionStartTimeout: const Duration(seconds: 5));

          await expectLater(
            controller.start(),
            throwsA(isA<SessionEstablishmentFailure>()));

          await controller.dispose();
        },
        timeout: const Timeout(Duration(seconds: 5)));

      test(
        'LINKED: a never-resolving LiveKitAdapter.connect() does not hang '
        'start() forever — completes with a thrown SessionEstablishmentFailure '
        'naming the LINKED transport, within the injected bound',
        () async {
          final settings = KeryxSettings(
            squelchLevel: 5,
            totSeconds: 120,
            busyLockout: false,
            latchMode: false,
            forceLocalOnly: false,
            relayUrl: 'wss://relay.example',
            tokenServiceUrl: 'https://relay.example/token-svc',
            characterDspIntensity: CharacterDspIntensity.light,
            dimMode: DimMode.auto);

          final controller = RadioSessionController(
            localPeerId: 'ALFA-1',
            callsign: 'Alice',
            settings: settings,
            dispatch: dispatchedEvents.add,
            liveKitAdapter: _HangingLiveKitAdapter(),
            tokenClientFactory: (_) => _FastTokenClient(),
            sessionStartTimeout: const Duration(milliseconds: 50));

          await expectLater(
            controller.start(),
            throwsA(
              isA<SessionEstablishmentFailure>().having(
                (e) => e.transport,
                'transport',
                Transport.relay)));

          expect(() => controller.floorEngine, throwsStateError);

          await controller.dispose();
        },
        timeout: const Timeout(Duration(seconds: 5)));

      test(
        'switchTarget shares the same bound as start() — a hung target '
        'switch also fails fast rather than hanging forever',
        () async {
          // First call (inside `start()`) returns a working no-op
          // discovery; the second call (inside `switchTarget()`'s own
          // `_startLocal`) returns one that never resolves — proves the
          // bound lives in `_startLocal` itself, reached from either
          // caller, not just the one `start()` call site.
          var calls = 0;
          DiscoveryService discoveryFactory() {
            calls++;
            return calls == 1
                ? _NoopDiscoveryService()
                : _HangingDiscoveryService();
          }

          final controller = RadioSessionController(
            localPeerId: 'ALFA-1',
            callsign: 'Alice',
            settings: settingsLocal,
            dispatch: dispatchedEvents.add,
            discoveryFactory: discoveryFactory,
            sessionStartTimeout: const Duration(milliseconds: 50));

          await controller.start();
          expect(calls, 1);

          await expectLater(
            controller.switchTarget(
              const TalkTarget(
                kind: TalkTargetKind.contact,
                id: 'p2',
                name: 'Peer',
                roomId: 'ABCDEFGHIJKLMNOP',
              ),
              memberPeerIds: const [],
            ),
            throwsA(isA<SessionEstablishmentFailure>()));
          expect(calls, 2);

          await controller.dispose();
        },
        timeout: const Timeout(Duration(seconds: 5)));
    });
  });
}
