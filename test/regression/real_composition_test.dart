import 'dart:async';
import 'dart:convert' show base64Encode;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/settings/settings_screen.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;
import 'package:keryx/services/directory/directory.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/identity/memory_identity_store.dart';
import '../services/directory/fakes/fake_directory_server.dart';

/// TASK-058 — Verification §9: "A scoped mock test is not sufficient
/// evidence for a production wiring change; include a test that exercises
/// the actual composition when the defect concerns wiring."
///
/// Every other widget test in `test/app_shell/**` and `test/features/**`
/// overrides [radioHostProvider] wholesale with a scoped `FakeRadioHost`
/// (an interface-level double). That proves each screen consumes the
/// [RadioHost] contract correctly, but it never proves the real
/// composition root (`KeryxApp` -> `MobileAppShell` -> the real
/// `radioHostProvider` -> the real `KeryxRadioHost` -> a real `FloorEngine`)
/// actually wires together end to end.
///
/// This file closes that gap by pumping the *real* `KeryxApp` widget tree
/// with the *real* `radioHostProvider` construction (copied verbatim from
/// `lib/app_shell/radio_host_provider.dart`'s shape) and only substituting
/// the five factories `KeryxRadioHost` itself takes as constructor
/// injection seams for platform/native boundaries that `flutter test`
/// cannot execute (Verification §2: "Use fake SessionHost, audio sink,
/// identity and permission/service adapters for deterministic widget
/// tests. Never require real UDP sockets or native plugin availability").
/// Everything above those five factories — `MaterialApp`, routing,
/// `MobileAppShell`, both Wave-4 destinations, `KeryxRadioHost`'s own
/// lifecycle logic, `radioStateProvider`, `settingsProvider` — is the real
/// production class, not a test double.

/// A keyed-install identity store (Technical §8) — `OnboardingGate` skips
/// straight to `MobileAppShell` when `IdentityRepository.privateKeySeedKey`
/// already has a value, which is what every test below needs to reach Talk
/// without going through the onboarding chooser/create/restore flow this
/// task's own `Owned_Paths` covers separately (`onboarding_gate.dart`).
MemoryIdentityStore _keyedInstallIdentityStore() => MemoryIdentityStore(<String, String>{
      IdentityRepository.privateKeySeedKey:
          base64Encode(List<int>.filled(32, 7)),
      IdentityRepository.callsignKey: 'TEST-01',
    });

void main() {
  setUp(() {
    // `contactsControllerProvider`/`groupsControllerProvider` (built
    // unconditionally by `MobileAppShell`'s `IndexedStack`, regardless of
    // which tab is active) both read `SharedPreferences.getInstance()` —
    // mock its platform channel or that future never resolves under
    // `flutter test`.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Widget buildRealApp({required _RealCompositionHarness harness}) {
    return ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        // `MobileAppShell`'s `IndexedStack` always builds Contacts/Groups —
        // stub `identityProvider` so that build never reaches the real
        // `flutter_secure_storage` platform channel (no mock handler under
        // `flutter test`; see `test/app_shell/shell_harness.dart`'s own
        // fix for the identical hang).
        identityProvider.overrideWith(
          (ref) async => DeviceIdentity(
            installUuid: '00000000-0000-4000-8000-000000000000',
            peerId: 'real-composition-stub-peer',
            callsign: Callsign.parse('STUB-1'))),
        // The only override in this file that touches `radioHostProvider`
        // itself — and it still constructs a real `KeryxRadioHost`, wired
        // to the same `settingsProvider`/`radioStateProvider` the
        // production provider reads, with only the five native/platform
        // factories swapped for deterministic fakes.
        radioHostProvider.overrideWith((ref) {
          final host = KeryxRadioHost(
            sessionFactory: harness.sessionFactory,
            audioSinkFactory: harness.audioSinkFactory,
            audioSinkDisposer: harness.audioSinkDisposer,
            identityFactory: harness.identityFactory,
            permissionGateFactory: harness.permissionGateFactory,
            radioServiceFactory: harness.radioServiceFactory,
            loadSettings: () => ref.read(settingsProvider.future),
            dispatch: (event) => ref.read(radioStateProvider.notifier).dispatch(event),
            readRadioState: () => ref.read(radioStateProvider),
            listenRadioState: (onChange, {bool fireImmediately = false}) {
              final subscription = ref.listen<RadioState>(
                radioStateProvider,
                (previous, next) => onChange(previous, next),
                fireImmediately: fireImmediately);
              return subscription.close;
            },
            listenSettings: (onChange) {
              final subscription = ref.listen<AsyncValue<KeryxSettings>>(
                settingsProvider,
                (previous, next) {
                  final settings = next.valueOrNull;
                  if (settings != null) onChange(settings);
                });
              return subscription.close;
            });
          ref.onDispose(() => unawaited(host.dispose()));
          return host;
        }),
      ],
      // The real `KeryxApp` — its own `MaterialApp`, theming, route table
      // and `MobileAppShell` composition, completely unmodified. A keyed
      // identity store so `OnboardingGate` passes straight through to
      // `MobileAppShell` (see `_keyedInstallIdentityStore`'s doc).
      child: KeryxApp(identityStore: _keyedInstallIdentityStore()));
  }

  testWidgets(
    'the real KeryxApp boots through the real radioHostProvider/'
    'KeryxRadioHost/FloorEngine wiring and lands on Talk with no '
    'construction error (Verification §9 real-composition requirement; '
    'ADR-002 §2 O1: Talk is the default destination on every launch)',
    (tester) async {
      final harness = _RealCompositionHarness();
      await tester.pumpWidget(buildRealApp(harness: harness));
      // First frame triggers `MobileAppShell.initState`'s microtask boot.
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'the real composition must not throw during boot');
      expect(find.byType(talkui.TalkScreen), findsOneWidget);
      expect(find.textContaining('Contacts need a relay address'), findsNothing);
      expect(
        harness.sessionHostsCreated,
        1,
        reason: 'exactly one real SessionHost must be constructed on boot');
      expect(harness.serviceControllersCreated, 1);
    });

  testWidgets(
    'navigating Talk -> Contacts -> Settings -> Talk through the real '
    'composition performs exactly one real session start and zero real '
    'retunes/disposals (VT-001, real KeryxRadioHost)',
    (tester) async {
      final harness = _RealCompositionHarness();
      await tester.pumpWidget(buildRealApp(harness: harness));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.sessionHostsCreated, 1);
      expect(harness.session!.startCalled, isTrue);
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      await tester.tap(find.byKey(ShellKeys.tabContacts));
      await tester.pumpAndSettle();
      expect(find.textContaining('Contacts need a relay address'), findsOneWidget);

      await tester.tap(find.byKey(ShellKeys.overflowMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShellKeys.overflowSettings));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Contacts need a relay address'), findsOneWidget);

      await tester.tap(find.byKey(ShellKeys.tabTalk));
      await tester.pumpAndSettle();
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      expect(
        harness.sessionHostsCreated,
        1,
        reason: 'navigation alone must never rebuild the real session');
      expect(
        harness.session!.retuneCallCount,
        0,
        reason: 'navigation alone must never retune the real session');
      expect(
        harness.session!.disposeCalled,
        isFalse,
        reason: 'navigation alone must never dispose the real session');
    });

  testWidgets(
    'disposing the real composition tears down the real session, floor '
    'engine and audio sink exactly once (VT-004, real KeryxRadioHost)',
    (tester) async {
      final harness = _RealCompositionHarness();
      await tester.pumpWidget(buildRealApp(harness: harness));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(harness.session, isNotNull);
      expect(harness.session!.disposeCalled, isFalse);

      // Unmount the whole tree -> ProviderScope disposes -> host.dispose().
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(harness.session!.disposeCalled, isTrue);
      expect(harness.audioSink!.stopAllCalled, isTrue);
    });

  testWidgets(
    'on-screen PTT and a simulated notification PTT action both act on the '
    'same real FloorEngine instance (VT-014, real KeryxRadioHost — closes '
    "TASK-069's routed gap: no test previously proved the new shell's "
    'on-screen and notification PTT entry points converge)',
    (tester) async {
      final harness = _RealCompositionHarness();
      await tester.pumpWidget(buildRealApp(harness: harness));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Talk is the default landing tab (ADR-002 §2 O1) — no navigation
      // needed to reach it.
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      final FloorEngine engine = harness.session!.floorEngine;
      expect(engine.isTransmitting, isFalse);

      // On-screen PTT: hold the disc.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))));
      await tester.pump();
      expect(
        engine.isTransmitting,
        isTrue,
        reason: 'on-screen PTT must reach the real, shared FloorEngine');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.isTransmitting, isFalse);

      // Simulated notification PTT action (a native toggle, not a hold) —
      // must land on the exact same FloorEngine instance the on-screen
      // disc just used, proving the two entry points converge rather than
      // each owning an independent engine.
      harness.serviceController!.emitEvent(const RadioServicePttAction());
      await tester.pumpAndSettle();
      expect(
        engine.isTransmitting,
        isTrue,
        reason:
            'notification PTT must toggle the same shared FloorEngine the '
            'on-screen disc just proved live, not a second instance');

      harness.serviceController!.emitEvent(const RadioServicePttAction());
      await tester.pumpAndSettle();
      expect(engine.isTransmitting, isFalse);
    });

  testWidgets(
    'switching away from the Talk tab does not stop the native radio '
    'service (notification PTT action stays reachable) — VT-014',
    (tester) async {
      final harness = _RealCompositionHarness();
      await tester.pumpWidget(buildRealApp(harness: harness));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      // Talk is the default landing tab (ADR-002 §2 O1).
      expect(find.byType(talkui.TalkScreen), findsOneWidget);
      expect(harness.serviceController!.isRunning, isTrue);

      await tester.tap(find.byKey(ShellKeys.tabContacts));
      await tester.pumpAndSettle();
      expect(find.textContaining('Contacts need a relay address'), findsOneWidget);

      expect(
        harness.serviceController!.isRunning,
        isTrue,
        reason:
            'leaving the Talk tab must not stop the foreground '
            'service/notification — its PTT action must remain reachable '
            'while off-screen (IndexedStack keeps Talk mounted, not '
            'disposed)');
    });

  testWidgets(
    'the real KeryxApp boots against a stubbed directory backend and '
    'reaches Talk (Verification G3)',
    (tester) async {
      HttpOverrides.global = null;
      late FakeDirectoryServer server;
      late IdentityKeyPair keyPair;
      late DirectoryClient directoryClient;
      late PresenceClient presenceClient;
      // Real `dart:io` socket setup/teardown must run inside `runAsync`'s
      // real zone, including `close()` — an `addTearDown`d async close ran
      // inside the fake-async test zone left a pending `HttpServer` idle
      // timer that failed this test's own invariant check on other runs.
      await tester.runAsync(() async {
        server = await FakeDirectoryServer.start();
        keyPair = await IdentityKeyPair.generate();
        directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
        presenceClient = PresenceClient(baseUrl: server.baseUrl, keyPair: keyPair);
      });
      addTearDown(() => tester.runAsync(() async {
            directoryClient.close();
            presenceClient.dispose();
            await server.close();
          }));
      server.responder = (RecordedDirectoryRequest req) {
        if (req.method == 'GET' && req.path == '/v2/identity/me') {
          return const DirectoryFakeResponse(
            statusCode: 200,
            body: <String, Object?>{
              'pk': 'me',
              'callsign': 'STUB-1',
              'status': 'available',
              'contacts': <Object?>[],
              'pending_in': <Object?>[],
              'pending_out': <Object?>[],
              'groups': <Object?>[],
            });
        }
        return const DirectoryFakeResponse(statusCode: 200, body: <String, Object?>{});
      };

      final harness = _RealCompositionHarness();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
            identityProvider.overrideWith(
              (ref) async => DeviceIdentity(
                installUuid: '00000000-0000-4000-8000-000000000000',
                peerId: derivePeerId(keyPair.publicKey),
                callsign: Callsign.parse('STUB-1'),
                keyPair: keyPair)),
            directoryClientProvider.overrideWith((ref) async => directoryClient),
            presenceClientProvider.overrideWith((ref) async => presenceClient),
            radioHostProvider.overrideWith((ref) {
              final host = KeryxRadioHost(
                sessionFactory: harness.sessionFactory,
                audioSinkFactory: harness.audioSinkFactory,
                audioSinkDisposer: harness.audioSinkDisposer,
                identityFactory: harness.identityFactory,
                permissionGateFactory: harness.permissionGateFactory,
                radioServiceFactory: harness.radioServiceFactory,
                loadSettings: () => ref.read(settingsProvider.future),
                dispatch: (event) =>
                    ref.read(radioStateProvider.notifier).dispatch(event),
                readRadioState: () => ref.read(radioStateProvider),
                listenRadioState: (onChange, {bool fireImmediately = false}) {
                  final subscription = ref.listen<RadioState>(
                    radioStateProvider,
                    (previous, next) => onChange(previous, next),
                    fireImmediately: fireImmediately);
                  return subscription.close;
                },
                listenSettings: (onChange) {
                  final subscription = ref.listen<AsyncValue<KeryxSettings>>(
                    settingsProvider,
                    (previous, next) {
                      final settings = next.valueOrNull;
                      if (settings != null) onChange(settings);
                    });
                  return subscription.close;
                });
              ref.onDispose(() => unawaited(host.dispose()));
              return host;
            }),
          ],
          child: KeryxApp(identityStore: _keyedInstallIdentityStore())));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a stubbed directory backend must not throw during boot');
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      await tester.tap(find.byKey(ShellKeys.tabContacts));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Contacts need a relay address'),
        findsNothing,
        reason: 'a stubbed directory client must reach the real Contacts '
            'tab body, not the no-relay empty state');

      await tester.tap(find.byKey(ShellKeys.tabTalk));
      await tester.pumpAndSettle();
      expect(find.byType(talkui.TalkScreen), findsOneWidget);
    });
}

/// Counts real construction calls and exposes the last-built real
/// [SessionHost]/[AudioSink] doubles so assertions can inspect authoritative
/// state, mirroring `test/core/radio_host/keryx_radio_host_test.dart`'s own
/// fakes in shape (that file's classes are private to it, so this is a
/// from-scratch, task-owned equivalent under `test/regression/**`, not a
/// cross-file import).
class _RealCompositionHarness {
  int sessionHostsCreated = 0;
  int serviceControllersCreated = 0;
  _RealSessionHost? session;
  _RealAudioSink? audioSink;
  _RealServiceController? serviceController;

  SessionHost sessionFactory({
    required String localPeerId,
    required String callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
  }) {
    sessionHostsCreated++;
    final host = _RealSessionHost(localPeerId: localPeerId, callsign: callsign);
    session = host;
    return host;
  }

  Future<AudioSink> audioSinkFactory() async {
    final sink = _RealAudioSink();
    audioSink = sink;
    return sink;
  }

  Future<void> audioSinkDisposer(AudioSink sink) async {
    if (sink is _RealAudioSink) sink.stopAll();
  }

  Future<DeviceIdentity> identityFactory() async => DeviceIdentity(
        installUuid: 'test-install-uuid',
        peerId: 'test-peer',
        callsign: Callsign.parse('TEST-01'));

  FacePermissionGate permissionGateFactory() => const _RealPermissionGate();

  RadioServiceController radioServiceFactory() {
    serviceControllersCreated++;
    final controller = _RealServiceController();
    serviceController = controller;
    return controller;
  }
}

class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void dispose() => unawaited(_incoming.close());
}

class _RealSessionHost implements SessionHost {
  _RealSessionHost({required this.localPeerId, required this.callsign}) {
    _engine.updateRoster({localPeerId});
  }

  final String localPeerId;
  final String callsign;
  bool startCalled = false;
  bool disposeCalled = false;
  int retuneCallCount = 0;

  final _NullFloorTransport _transport = _NullFloorTransport();
  late final FloorEngine _engine = FloorEngine(
    localPeerId: localPeerId,
    transport: _transport,
    clock: const WallClock(),
    tot: const Duration(seconds: 60),
    busyLockout: true,
    callsign: callsign);

  final _stations = StreamController<List<StationInfo>>.broadcast();

  @override
  FloorEngine get floorEngine => _engine;

  @override
  Stream<List<StationInfo>> get stations => _stations.stream;

  @override
  Future<void> start() async {
    startCalled = true;
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    _engine.dispose();
    _transport.dispose();
    await _stations.close();
  }
}

class _RealAudioSink implements AudioSink {
  bool stopAllCalled = false;

  @override
  void playOneShot({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    double gain = 1.0,
  }) {}

  @override
  void startLoop({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    required Duration loopStart,
    required Duration loopEnd,
    double gain = 1.0,
  }) {}

  @override
  void setLoopGain(SfxId id, double gain) {}

  @override
  void stop(SfxId id) {}

  @override
  void setBusGainDb(AudioBus bus, double gainDb) {}

  @override
  void stopAll() {
    stopAllCalled = true;
  }
}

class _RealPermissionGate implements FacePermissionGate {
  const _RealPermissionGate();

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

class _RealServiceController implements RadioServiceController {
  final _events = StreamController<RadioServiceEvent>.broadcast();
  bool _running = false;

  /// Lets a test simulate a native notification-PTT/power-off/kill event
  /// arriving from the platform channel, exactly as `ChannelRadioServiceController`
  /// would surface one.
  void emitEvent(RadioServiceEvent event) => _events.add(event);

  @override
  Stream<RadioServiceEvent> get events => _events.stream;

  @override
  bool get isRunning => _running;

  @override
  bool? get pttActionEnabled => null;

  @override
  Future<RadioServiceStartInfo> start({
    required String channelLabel,
    String? subtitle,
  }) async {
    _running = true;
    return const RadioServiceStartInfo(pttActionEnabled: true);
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  @override
  Future<void> setPhase(RadioTransportPhase phase) async {}

  @override
  Future<void> updateNotification({
    required String channelLabel,
    String? subtitle,
  }) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}
