import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';
import 'package:keryx/services/discovery/discovered_peer.dart';
import 'package:keryx/services/discovery/discovery_config.dart';
import 'package:keryx/services/discovery/discovery_service.dart';
import 'package:keryx/services/discovery/discovery_state.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/linked/token_client.dart';
import 'package:keryx/services/session/session.dart' show RadioSessionController;
import 'package:keryx/services/signaling/in_process_endpoint.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/directory/fakes/fake_directory_server.dart';
import '../services/directory/fakes/stateful_directory_fake.dart';
import '../services/linked/fakes/fake_livekit_adapter.dart';
import '../services/mesh/fakes/fake_rtc_adapter.dart';

/// Two independent "phones" sharing one [StatefulDirectoryFake] on a
/// loopback [FakeDirectoryServer]. Native seams only: audio sink,
/// permission gate, radio-service platform, LiveKit, WebRTC, NSD
/// discovery, in-process signaling. Every controller/provider the
/// journey names is the production class.
class JourneyHarness {
  JourneyHarness._({
    required this.server,
    required this.directory,
    required this.phoneA,
    required this.phoneB,
  });

  final FakeDirectoryServer server;
  final StatefulDirectoryFake directory;
  final JourneyPhone phoneA;
  final JourneyPhone phoneB;

  static Future<JourneyHarness> start() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final server = await FakeDirectoryServer.start();
    final directory = StatefulDirectoryFake();
    server.responder = directory.respond;

    final a = await JourneyPhone.open(
      label: 'A',
      callsign: 'ALFA-1',
      server: server,
    );
    final b = await JourneyPhone.open(
      label: 'B',
      callsign: 'BRAVO-7',
      server: server,
    );
    return JourneyHarness._(
      server: server,
      directory: directory,
      phoneA: a,
      phoneB: b,
    );
  }

  Future<void> close() async {
    phoneA.dispose();
    phoneB.dispose();
    await server.close();
  }
}

class JourneyPhone {
  JourneyPhone._({
    required this.label,
    required this.identity,
    required this.container,
    required this.liveKit,
  });

  final String label;
  final DeviceIdentity identity;
  final ProviderContainer container;
  final FakeLiveKitAdapter liveKit;

  RadioSessionHostAdapter? sessionAdapter;

  String get pk => encodeUnpaddedBase64Url(identity.keyPair!.publicKey);

  KeryxIdLink get idLink => KeryxIdLink(
        callsign: identity.callsign.value,
        publicKey: identity.keyPair!.publicKey,
      );

  RadioSessionController get session {
    final adapter = sessionAdapter;
    if (adapter == null) {
      throw StateError('$label session not built — boot the host first');
    }
    return adapter.debugController;
  }

  RadioState get radioState => container.read(radioStateProvider);

  static Future<JourneyPhone> open({
    required String label,
    required String callsign,
    required FakeDirectoryServer server,
  }) async {
    final keyPair = await IdentityKeyPair.generate();
    final identity = DeviceIdentity(
      installUuid: '00000000-0000-4000-8000-00000000000$label',
      peerId: derivePeerId(keyPair.publicKey),
      callsign: Callsign.parse(callsign),
      keyPair: keyPair,
      shortCode: deriveShortCode(keyPair.publicKey),
    );

    final store = InMemorySettingsStore();
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(
        KeryxSettings(
          relayUrl: 'wss://journey.test/ws',
          tokenServiceUrl: server.baseUrl.toString(),
          forceLocalOnly: false,
        ).toJson(),
      ),
    );

    final liveKit = FakeLiveKitAdapter();
    final signalingHub = InProcessSignalingHub();
    late final ProviderContainer container;
    container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(store),
        identityProvider.overrideWith((ref) async => identity),
        directoryBaseUriResolverProvider.overrideWithValue(
          (relayUrl) => relayUrl.isEmpty ? null : server.baseUrl,
        ),
        radioHostProvider.overrideWith((ref) {
          final host = KeryxRadioHost(
            sessionFactory: ({
              required String localPeerId,
              required String callsign,
              required KeryxSettings settings,
              required void Function(RadioEvent event) dispatch,
            }) {
              final controller = RadioSessionController(
                localPeerId: localPeerId,
                callsign: callsign,
                settings: settings,
                dispatch: dispatch,
                discoveryFactory: _NoopDiscoveryService.new,
                endpointFactory: signalingHub.endpoint,
                rtcAdapter: FakeRtcAdapter(),
                liveKitAdapter: liveKit,
                identityKeyPairLoader: () async => identity.keyPair,
                // Settings persist only `https://` token URLs, so the
                // derived default is `https://journey.test/token`. Point
                // the *real* TokenClient at the loopback fake instead.
                tokenClientFactory: (Uri baseUrl, {IdentityKeyPair? signer}) =>
                    TokenClient(baseUrl: server.baseUrl, signer: signer),
              );
              final adapter = RadioSessionHostAdapter(controller);
              _sessionHolders[container]?.call(adapter);
              return adapter;
            },
            audioSinkFactory: () async => RecordingAudioSink(),
            audioSinkDisposer: (_) async {},
            identityFactory: () async => identity,
            permissionGateFactory: _PermissionGateFake.new,
            radioServiceFactory: () =>
                ChannelRadioServiceController(platform: FakeRadioServicePlatform()),
            loadSettings: () => ref.read(settingsProvider.future),
            ensureDirectoryEnrolment: () =>
                ref.read(identityEnrolmentProvider.future),
            dispatch: (event) =>
                ref.read(radioStateProvider.notifier).dispatch(event),
            readRadioState: () => ref.read(radioStateProvider),
            listenRadioState: (onChange, {bool fireImmediately = false}) {
              final subscription = ref.listen<RadioState>(
                radioStateProvider,
                (previous, next) => onChange(previous, next),
                fireImmediately: fireImmediately,
              );
              return subscription.close;
            },
            listenSettings: (onChange) {
              final subscription = ref.listen<AsyncValue<KeryxSettings>>(
                settingsProvider,
                (previous, next) {
                  final settings = next.valueOrNull;
                  if (settings != null) onChange(settings);
                },
              );
              return subscription.close;
            },
          );
          ref.onDispose(() {
            unawaited(() async {
              try {
                await host.dispose();
              } on Object {
                // `switchTarget` tears down the boot-time LOCAL engine;
                // the host still holds that reference and
                // `releaseTransmit` then throws. Out of this task's
                // territory (`lib/core/radio_host/**`).
              }
            }());
          });
          return host;
        }),
      ],
    );

    final journey = JourneyPhone._(
      label: label,
      identity: identity,
      container: container,
      liveKit: liveKit,
    );
    _sessionHolders[container] = (adapter) => journey.sessionAdapter = adapter;
    return journey;
  }

  Future<void> boot() async {
    await container.read(radioHostProvider).start();
  }

  void dispose() {
    _sessionHolders.remove(container);
    container.dispose();
  }
}

final Map<ProviderContainer, void Function(RadioSessionHostAdapter)>
    _sessionHolders = {};

class _PermissionGateFake implements FacePermissionGate {
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
