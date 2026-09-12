import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/clock.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/discovery/channel_hash_prefix.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/discovery/discovery_state.dart';
import 'package:keryx/services/mesh/rtc_adapter.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart';
import 'package:keryx/services/signaling/in_process_endpoint.dart';

import '../../services/mesh/fakes/fake_rtc_adapter.dart';

/// TASK-079/ADR-002 A6 — proves `KeryxRadioHost` actually reaches the
/// meter-level value out of a *real* `RadioSessionController` via the
/// `RadioSessionHostAdapter.debugController` seam (see `keryx_radio_host
/// .dart`'s dartdoc on that cast for why this is the sanctioned route
/// rather than widening `SessionHost`, which is outside this task's
/// `Owned_Paths`). `keryx_radio_host_test.dart`'s own harness uses a
/// hand-written `SessionHost` double (not a `RadioSessionHostAdapter`) for
/// everything else, which is exactly why this needs its own file: the cast
/// branch is otherwise never exercised.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeryxRadioHost meter-level wiring (TASK-079)', () {
    late InProcessSignalingHub sigHub;
    late VirtualClock clockA;
    late FakeRtcAdapter adapterA;
    late FakeRtcAdapter adapterB;
    late RadioSessionController controllerA;
    late RadioSessionController controllerB;
    late KeryxRadioHost host;
    final channelHashPrefix = ChannelHashPrefix.compute(
      region: 'US',
      channel: '1',
      code: '0',
    );

    const settings = KeryxSettings(
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

    RadioState state = const RadioState.off();

    setUp(() async {
      state = const RadioState.off();
      sigHub = InProcessSignalingHub();
      clockA = VirtualClock();
      adapterA = FakeRtcAdapter();
      adapterB = FakeRtcAdapter();

      controllerB = RadioSessionController(
        localPeerId: 'BRAVO-7',
        callsign: 'Bravo',
        settings: settings,
        dispatch: (RadioEvent event) {},
        initialChannel: 1,
        initialCode: 0,
        endpointFactory: sigHub.endpoint,
        discoveryFactory: _NoopDiscoveryService.new,
        rtcAdapter: adapterB,
      );
      await controllerB.start();

      host = KeryxRadioHost(
        sessionFactory:
            ({
              required String localPeerId,
              required String callsign,
              required KeryxSettings settings,
              required void Function(RadioEvent event) dispatch,
              required int initialChannel,
              required int initialCode,
            }) {
              controllerA = RadioSessionController(
                localPeerId: localPeerId,
                callsign: callsign,
                settings: settings,
                dispatch: dispatch,
                initialChannel: initialChannel,
                initialCode: initialCode,
                clock: clockA,
                endpointFactory: sigHub.endpoint,
                discoveryFactory: _NoopDiscoveryService.new,
                rtcAdapter: adapterA,
              );
              return RadioSessionHostAdapter(controllerA);
            },
        audioSinkFactory: () async => RecordingAudioSink(),
        audioSinkDisposer: (AudioSink sink) async {},
        identityFactory: () async => DeviceIdentity(
          installUuid: 'uuid',
          peerId: 'ALFA-1',
          callsign: Callsign.parse('ALFA-1'),
        ),
        permissionGateFactory: () => _FakePermissionGate(),
        radioServiceFactory: () =>
            ChannelRadioServiceController(platform: FakeRadioServicePlatform()),
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
        rememberChannel: (channel) async => settings,
      );
      await host.start();

      // Real signaling handshake so controllerA's MeshController opens a
      // (faked) connection + data channel to BRAVO-7 — same technique as
      // `radio_session_controller_test.dart`'s own RX-level group.
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
      controllerA.floorEngine.updateRoster({'ALFA-1', 'BRAVO-7'});
    });

    tearDown(() async {
      await host.dispose();
      await controllerB.dispose();
    });

    test('snapshot starts decorative', () {
      expect(host.current.meterLevel, MeterLevel.decorative);
    });

    test(
      'a real controller meter-level change reaches RadioHostSnapshot and '
      'fires `changes`',
      () async {
        adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
          RtcRemoteAudioTrack(
            id: 'bravo-remote',
            readAudioLevel: () async => const RtcMeasuredAudioLevel(0.6),
          ),
        );

        final snapshots = <RadioHostSnapshot>[];
        final sub = host.changes.listen(snapshots.add);

        adapterA.connectionsCreated.single.dataChannel!.deliver(
          FloorCodec.encode(const TxStart(peer: 'BRAVO-7')),
        );
        await _flush();
        clockA.elapse(const Duration(milliseconds: 100));
        await _flush();

        expect(host.current.meterLevel, isA<MeasuredMeterLevel>());
        expect(
          (host.current.meterLevel as MeasuredMeterLevel).value,
          closeTo(60, 0.001),
        );
        expect(
          snapshots.any((s) => s.meterLevel is MeasuredMeterLevel),
          isTrue,
          reason: '`changes` must have re-emitted on the meter-level update',
        );

        adapterA.connectionsCreated.single.dataChannel!.deliver(
          FloorCodec.encode(const TxEnd(peer: 'BRAVO-7')),
        );
        await _flush();
        expect(host.current.meterLevel, MeterLevel.decorative);

        await sub.cancel();
      },
    );

    test('dispose cancels the meter-level subscription cleanly', () async {
      adapterA.connectionsCreated.single.deliverRemoteAudioTrack(
        RtcRemoteAudioTrack(
          id: 'bravo-remote',
          readAudioLevel: () async => const RtcMeasuredAudioLevel(0.2),
        ),
      );
      adapterA.connectionsCreated.single.dataChannel!.deliver(
        FloorCodec.encode(const TxStart(peer: 'BRAVO-7')),
      );
      await _flush();
      clockA.elapse(const Duration(milliseconds: 100));
      await _flush();
      expect(host.current.meterLevel, isA<MeasuredMeterLevel>());

      await host.dispose();
      // Idempotent — a second dispose must not throw.
      await host.dispose();
    });
  });
}
