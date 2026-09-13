import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/discovery/discovery_state.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart';
import 'package:keryx/services/signaling/in_process_endpoint.dart';

import '../../services/mesh/fakes/fake_rtc_adapter.dart';

/// TASK-107: real `RadioSessionController` + `RadioSessionHostAdapter` +
/// `KeryxRadioHost` — the production chain the journey uses.
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

class _FakePermissionGate implements FacePermissionGate {
  @override
  Future<FacePermissionOutcome> ensureMicrophone() async =>
      FacePermissionOutcome.granted;

  @override
  Future<FacePermissionOutcome> ensureNotifications() async =>
      FacePermissionOutcome.granted;

  @override
  Future<FacePermissionOutcome> ensureNearbyWifiDevices() async =>
      FacePermissionOutcome.granted;
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeryxRadioHost re-adopts engine after switchTarget (TASK-107)', () {
    late InProcessSignalingHub sigHub;
    late FakeRtcAdapter adapter;
    late RadioSessionController controller;
    late KeryxRadioHost host;
    late RadioState state;

    const settings = KeryxSettings(
      squelchLevel: 5,
      totSeconds: 120,
      busyLockout: false,
      latchMode: false,
      forceLocalOnly: false,
      relayUrl: '',
      tokenServiceUrl: '',
      characterDspIntensity: CharacterDspIntensity.light,
      dimMode: DimMode.auto,
    );

    setUp(() async {
      state = const RadioState.off();
      sigHub = InProcessSignalingHub();
      adapter = FakeRtcAdapter();
      host = KeryxRadioHost(
        sessionFactory: ({
          required String localPeerId,
          required String callsign,
          required KeryxSettings settings,
          required void Function(RadioEvent event) dispatch,
        }) {
          controller = RadioSessionController(
            localPeerId: localPeerId,
            callsign: callsign,
            settings: settings,
            dispatch: dispatch,
            endpointFactory: sigHub.endpoint,
            discoveryFactory: _NoopDiscoveryService.new,
            rtcAdapter: adapter,
          );
          return RadioSessionHostAdapter(controller);
        },
        audioSinkFactory: () async => RecordingAudioSink(),
        audioSinkDisposer: (AudioSink sink) async {},
        identityFactory: () async => DeviceIdentity(
          installUuid: 'uuid',
          peerId: 'ALFA-1',
          callsign: Callsign.parse('ALFA-1'),
        ),
        permissionGateFactory: () => _FakePermissionGate(),
        radioServiceFactory: () => ChannelRadioServiceController(
          platform: FakeRadioServicePlatform(),
        ),
        loadSettings: () async => settings,
        dispatch: (RadioEvent event) {
          state = const RadioReducer().reduce(state, event);
        },
        readRadioState: () => state,
        listenRadioState: (onChange, {bool fireImmediately = false}) {
          if (fireImmediately) onChange(null, state);
          return () {};
        },
        listenSettings: (onChange) => () {},
      );
      await host.start();
    });

    tearDown(() async {
      await host.dispose();
    });

    test(
      'after switchTarget, snapshot.floorEngine is the controller engine '
      'and pressPtt reaches RadioPhase.tx with no exception',
      () async {
        final bootEngine = host.current.floorEngine;
        expect(bootEngine, same(controller.floorEngine));

        await controller.switchTarget(
          const TalkTarget(
            kind: TalkTargetKind.contact,
            id: 'bravo-pk',
            name: 'BRAVO-7',
            roomId: 'v2-room-ptt01',
          ),
          memberPeerIds: const [],
        );
        await _flush();

        expect(host.current.floorEngine, same(controller.floorEngine));
        expect(identical(host.current.floorEngine, bootEngine), isFalse);

        expect(() => host.pressPtt(), returnsNormally);
        await _flush();
        expect(controller.floorEngine.isTransmitting, isTrue);
        expect(state.phase, RadioPhase.tx);

        expect(() => host.releasePtt(), returnsNormally);
        await _flush();
        expect(controller.floorEngine.isTransmitting, isFalse);
        expect(state.phase, isNot(RadioPhase.tx));
      },
    );

    test(
      'host.current.floorEngine stays identical to the controller after '
      'switchTarget even without a microtask flush (sync engineChanges)',
      () async {
        await controller.switchTarget(
          const TalkTarget(
            kind: TalkTargetKind.contact,
            id: 'bravo-pk',
            name: 'BRAVO-7',
            roomId: 'v2-room-sync01',
          ),
          memberPeerIds: const ['BRAVO-7'],
        );
        expect(host.current.floorEngine, same(controller.floorEngine));
      },
    );
  });
}
