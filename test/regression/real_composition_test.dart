import 'dart:async';

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
import 'package:keryx/features/channels/channels_landing.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/face/permission_gate.dart';
import 'package:keryx/features/face/session_host.dart';
import 'package:keryx/features/settings/settings_screen.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

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
void main() {
  Widget buildRealApp({required _RealCompositionHarness harness}) {
    return ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
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
            rememberChannel: (channel) =>
                ref.read(settingsProvider.notifier).rememberChannel(channel),
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
          ref.onDispose(() => unawaited(host.dispose()));
          return host;
        }),
      ],
      // The real `KeryxApp` — its own `MaterialApp`, theming, route table
      // and `MobileAppShell` composition, completely unmodified.
      child: const KeryxApp(),
    );
  }

  testWidgets(
    'the real KeryxApp boots through the real radioHostProvider/'
    'KeryxRadioHost/FloorEngine wiring and lands on Channels with no '
    'construction error (Verification §9 real-composition requirement)',
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
        reason: 'the real composition must not throw during boot',
      );
      expect(find.byType(ChannelsLanding), findsOneWidget);
      expect(
        harness.sessionHostsCreated,
        1,
        reason: 'exactly one real SessionHost must be constructed on boot',
      );
      expect(harness.serviceControllersCreated, 1);
    },
  );

  testWidgets(
    'navigating Channels -> Talk -> Settings -> Talk through the real '
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

      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Channels'),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ChannelsLandingKeys.openTalk));
      await tester.pumpAndSettle();
      expect(find.byType(talkui.TalkScreen), findsOneWidget);

      expect(
        harness.sessionHostsCreated,
        1,
        reason: 'navigation alone must never rebuild the real session',
      );
      expect(
        harness.session!.retuneCallCount,
        0,
        reason: 'navigation alone must never retune the real session',
      );
      expect(
        harness.session!.disposeCalled,
        isFalse,
        reason: 'navigation alone must never dispose the real session',
      );
    },
  );

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
    },
  );
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

  SessionHost sessionFactory({
    required String localPeerId,
    required String callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
    required int initialChannel,
    required int initialCode,
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
        callsign: Callsign.parse('TEST-01'),
      );

  FacePermissionGate permissionGateFactory() => const _RealPermissionGate();

  RadioServiceController radioServiceFactory() {
    serviceControllersCreated++;
    return _RealServiceController();
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
    callsign: callsign,
  );

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
  Future<void> retune({required int channel, required int code}) async {
    retuneCallCount++;
  }

  @override
  Future<void> joinEvent(EventLinkPayload payload) async {}

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
