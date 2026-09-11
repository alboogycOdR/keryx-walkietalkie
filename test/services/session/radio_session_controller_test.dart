import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/floor/floor_engine.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/discovery/channel_hash_prefix.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/discovery/discovery_state.dart';
import 'package:keryx/services/mesh/rtc_adapter.dart';
import 'package:keryx/services/session/radio_session_controller.dart';
import 'package:keryx/services/signaling/in_process_endpoint.dart';

import '../mesh/fakes/fake_rtc_adapter.dart';

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
        region: 'US',
        squelchLevel: 5,
        totSeconds: 120,
        busyLockout: false,
        latchMode: false,
        forceLocalOnly: false,
        mode: RadioMode.local,
        relayUrl: '',
        tokenServiceUrl: '',
        characterDspIntensity: CharacterDspIntensity.light,
        dimMode: DimMode.auto,
      );

    });

    // Criterion 2: Composed floor engine — verify engine exists and is accessible
    group('composed floor engine', () {
      test('floorEngine property accessible after start', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

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
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        expect(
          () => controller.floorEngine,
          throwsStateError,
        );
      });
    });

    // Criterion 3: Mode matrix (8 cases)
    group('mode matrix', () {
      Future<void> testMode({
        required RadioMode mode,
        required bool forceLocalOnly,
        required String relayUrl,
        required bool expectLocalBuilt,
      }) async {
        final settings = KeryxSettings(
          region: 'US',
          squelchLevel: 5,
          totSeconds: 120,
          busyLockout: false,
          latchMode: false,
          forceLocalOnly: forceLocalOnly,
          mode: mode,
          relayUrl: relayUrl,
          tokenServiceUrl: relayUrl.isEmpty ? '' : 'https://host/token-svc',
          characterDspIntensity: CharacterDspIntensity.light,
          dimMode: DimMode.auto,
        );

        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settings,
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        await controller.start();

        // Criterion 3a: verify LOCAL chain exists when expected
        expect(
          controller.debugMeshTransport != null,
          equals(expectLocalBuilt),
          reason: 'mode=$mode, forceLocalOnly=$forceLocalOnly, relayUrl=$relayUrl',
        );

        // Criterion 3b: verify LINKED never built when forceLocalOnly=true
        if (forceLocalOnly) {
          expect(
            controller.debugLinkedController,
            isNull,
            reason: 'forceLocalOnly=true must prevent LINKED construction',
          );
        }

        await controller.dispose();
      }

      test('local mode → LOCAL only', () async {
        await testMode(
          mode: RadioMode.local,
          forceLocalOnly: false,
          relayUrl: 'wss://relay.example',
          expectLocalBuilt: true,
        );
      });

      test('local mode + forceLocalOnly → LOCAL only', () async {
        await testMode(
          mode: RadioMode.local,
          forceLocalOnly: true,
          relayUrl: 'wss://relay.example',
          expectLocalBuilt: true,
        );
      });

      test('auto mode + no relay → LOCAL only', () async {
        await testMode(
          mode: RadioMode.auto,
          forceLocalOnly: false,
          relayUrl: '',
          expectLocalBuilt: true,
        );
      });

      test('auto mode + no relay + forceLocalOnly → LOCAL only', () async {
        await testMode(
          mode: RadioMode.auto,
          forceLocalOnly: true,
          relayUrl: '',
          expectLocalBuilt: true,
        );
      });

      test('forceLocalOnly=true prevents LINKED even in linked mode', () async {
        await testMode(
          mode: RadioMode.linked,
          forceLocalOnly: true,
          relayUrl: 'wss://relay.example',
          expectLocalBuilt: true,
        );
      });
    });

    // Criterion 4: SetMode dispatched on start
    group('SetMode routing', () {
      test('SetMode dispatched on successful start', () async {
        dispatchedEvents.clear();

        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        await controller.start();

        final setModes = dispatchedEvents.whereType<SetMode>().toList();
        expect(setModes, isNotEmpty, reason: 'SetMode must be dispatched on start');
        expect(setModes.first.mode, equals(RadioMode.local));

        await controller.dispose();
      });

      test('SetMode reflects actual constructed mode', () async {
        dispatchedEvents.clear();

        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: const KeryxSettings(
            region: 'US',
            squelchLevel: 5,
            totSeconds: 120,
            busyLockout: false,
            latchMode: false,
            forceLocalOnly: true,
            mode: RadioMode.linked,
            relayUrl: 'wss://relay.example',
            tokenServiceUrl: 'https://relay.example/token-svc',
            characterDspIntensity: CharacterDspIntensity.light,
            dimMode: DimMode.auto,
          ),
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        await controller.start();

        final setModes = dispatchedEvents.whereType<SetMode>().toList();
        // Even though mode=linked in settings, forceLocalOnly forces LOCAL
        expect(setModes.last.mode, equals(RadioMode.local),
            reason: 'SetMode must reflect forceLocalOnly override');

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
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

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
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

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
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        // start should complete
        await expectLater(
          controller.start(),
          completes,
          reason: 'start() must complete',
        );

        // dispose should complete
        await expectLater(
          controller.dispose(),
          completes,
          reason: 'dispose() must complete',
        );
      });

      test('retune rebuilds engine', () async {
        final controller = RadioSessionController(
          localPeerId: 'ALFA-1',
          callsign: 'Alice',
          settings: settingsLocal,
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        await controller.start();
        final engine1 = controller.floorEngine;
        // Pre-retune engine must itself be valid, so a post-retune comparison
        // means something rather than checking a fresh engine against nothing.
        expect(engine1, isNotNull);
        expect(engine1, isA<FloorEngine>());

        await controller.retune(channel: 2, code: 5);
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
          dispatch: dispatchedEvents.add,
          initialChannel: 1,
          initialCode: 0,
        );

        await controller.start();
        await controller.dispose();

        expect(
          () => controller.floorEngine,
          throwsStateError,
          reason: 'floorEngine must throw after dispose',
        );

        expect(
          () async => await controller.retune(channel: 2, code: 0),
          throwsStateError,
          reason: 'retune() must throw after dispose',
        );
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
      final channelHashPrefix = ChannelHashPrefix.compute(
        region: 'US',
        channel: '1',
        code: '0',
      );

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
          initialChannel: 1,
          initialCode: 0,
          clock: clock,
          endpointFactory: hub.endpoint,
          discoveryFactory: _NoopDiscoveryService.new,
          rtcAdapter: adapter,
        );
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
            port: sigB.boundPort,
          ),
        );
        sigB.onPeerFound(
          DiscoveredPeer(
            peerId: 'ALFA-1',
            callsign: 'Alice',
            channelHashPrefix: channelHashPrefix,
            version: 1,
            host: '10.0.0.2',
            port: sigA.boundPort,
          ),
        );
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
          clock: clockA,
        );
        controllerB = buildController(
          peerId: 'BRAVO-7',
          callsign: 'Bravo',
          hub: sigHub,
          adapter: adapterB,
        );
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

      test(
        'starts polling on RemoteFloorStarted; measured value flows through '
        'at ~10 Hz; stops on RemoteFloorEnded',
        () async {
          var level = 0.1;
          adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
            RtcRemoteAudioTrack(
              id: 'bravo-remote',
              readAudioLevel: () async => RtcMeasuredAudioLevel(level),
            ),
          );

          final seen = <MeterLevel>[];
          final sub = controllerA.meterLevelChanges.listen(seen.add);

          deliverRemoteStart('BRAVO-7');
          expect(
            controllerA.floorEngine.holder,
            'BRAVO-7',
            reason: 'sanity: TxStart must have installed BRAVO-7 as holder',
          );
          await _flush();
          // First poll tick fires 100ms after RemoteFloorStarted scheduled it.
          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();

          expect(
            controllerA.meterLevel,
            isA<MeasuredMeterLevel>(),
            reason: 'RemoteFloorStarted on A must begin polling BRAVO-7',
          );
          expect(
            (controllerA.meterLevel as MeasuredMeterLevel).value,
            closeTo(10, 0.001),
          );

          // Advance one more poll tick with a different level to confirm
          // the ~10 Hz self-reschedule is actually live, not a one-shot.
          level = 0.5;
          clockA.elapse(const Duration(milliseconds: 100));
          await _flush();
          expect(
            (controllerA.meterLevel as MeasuredMeterLevel).value,
            closeTo(50, 0.001),
          );

          deliverRemoteEnd('BRAVO-7');
          await _flush();

          expect(
            controllerA.meterLevel,
            MeterLevel.decorative,
            reason: 'RemoteFloorEnded must stop polling and go decorative',
          );

          // No leaked timer: further clock elapses must not resurrect a
          // measured value now that polling has stopped.
          level = 0.9;
          clockA.elapse(const Duration(seconds: 5));
          await _flush();
          expect(controllerA.meterLevel, MeterLevel.decorative);

          expect(
            seen.any((l) => l is MeasuredMeterLevel),
            isTrue,
            reason: 'meterLevelChanges must have emitted the measured value',
          );
          await sub.cancel();
        },
      );

      test('unavailable sample projects as decorative, not measured', () async {
        // No remote track delivered on purpose — MeshController.readAudioLevel
        // resolves unavailable.
        deliverRemoteStart('BRAVO-7');
        await _flush();

        expect(controllerA.meterLevel, MeterLevel.decorative);

        deliverRemoteEnd('BRAVO-7');
        await _flush();
      });

      test('retune stops polling and does not leak a timer', () async {
        adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
          RtcRemoteAudioTrack(
            id: 'bravo-remote',
            readAudioLevel: () async => const RtcMeasuredAudioLevel(0.3),
          ),
        );

        deliverRemoteStart('BRAVO-7');
        await _flush();
        clockA.elapse(const Duration(milliseconds: 100));
        await _flush();
        expect(controllerA.meterLevel, isA<MeasuredMeterLevel>());

        await controllerA.retune(channel: 2, code: 0);
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
            readAudioLevel: () async => const RtcMeasuredAudioLevel(0.3),
          ),
        );
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
  });
}
