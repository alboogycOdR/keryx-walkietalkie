import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

/// TASK-045 — `KeryxRadioHost` unit tests. Riverpod-free by construction
/// (see `radio_host.dart`'s library dartdoc): this harness supplies plain
/// callbacks standing in for `ref.read`/`ref.listenManual`, so every test
/// here runs without a `WidgetTester`/`ProviderScope` at all — a stronger,
/// faster proof of the host's own lifecycle contract than a widget test
/// could give, and the intended shape per Technical §2's "may use a
/// Riverpod Notifier... or a dedicated lifecycle service".
///
/// A silent, single-device [FloorTransport] — enough to satisfy
/// [FloorEngine]'s constructor without touching a real transport. Mirrors
/// `face_screen_test.dart`'s own `_NullFloorTransport` (that class is
/// private to its file, so this is a from-scratch equivalent, not a
/// cross-file import — test/core/radio_host/** is this task's own
/// territory).
class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void dispose() => unawaited(_incoming.close());
}

/// Hand-written [SessionHost] double.
class _FakeSessionHost implements SessionHost {
  _FakeSessionHost({required String label})
    : localPeerId = 'peer-$label',
      callsign = 'TEST $label' {
    // A constructor-default `{self}` roster does NOT set `_rosterDeclared`
    // (see `FloorEngine`'s own dartdoc) — a solo `requestTransmit()` needs
    // it declared before it can be granted synchronously.
    _engine.updateRoster({localPeerId});
  }

  final String localPeerId;
  final String callsign;

  final _NullFloorTransport _transport = _NullFloorTransport();
  late final FloorEngine _engine = FloorEngine(
    localPeerId: localPeerId,
    transport: _transport,
    clock: const WallClock(),
    tot: const Duration(seconds: 60),
    busyLockout: true,
    callsign: callsign);

  final StreamController<List<StationInfo>> _stations =
      StreamController<List<StationInfo>>.broadcast();

  bool startCalled = false;
  bool disposeCalled = false;

  @override
  FloorEngine get floorEngine => _engine;

  @override
  Stream<List<StationInfo>> get stations => _stations.stream;

  void emitStations(List<StationInfo> next) {
    if (!_stations.isClosed) _stations.add(next);
  }

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

class _FakePermissionGate implements FacePermissionGate {
  FacePermissionOutcome microphoneOutcome = FacePermissionOutcome.granted;

  @override
  Future<FacePermissionOutcome> ensureMicrophone() async => microphoneOutcome;

  @override
  Future<FacePermissionOutcome> ensureNotifications() async =>
      FacePermissionOutcome.granted;

  @override
  Future<FacePermissionOutcome> ensureNearbyWifiDevices() async =>
      FacePermissionOutcome.granted;
}

/// Riverpod-free harness: every [KeryxRadioHost] constructor callback is a
/// plain method here, standing in for `ref.read(...)`/`ref.listenManual`.
class _Harness {
  final List<_FakeSessionHost> sessions = <_FakeSessionHost>[];
  final RecordingAudioSink sink = RecordingAudioSink();
  final List<FakeRadioServicePlatform> servicePlatforms =
      <FakeRadioServicePlatform>[];
  final List<ChannelRadioServiceController> serviceControllers =
      <ChannelRadioServiceController>[];

  bool audioSinkDisposed = false;
  int identityFactoryCalls = 0;
  FacePermissionOutcome micOutcome = FacePermissionOutcome.granted;

  KeryxSettings settings = const KeryxSettings();
  RadioState state = const RadioState.off();
  final List<RadioEvent> dispatched = <RadioEvent>[];

  /// Populated by every `_FakeSessionHost.retune` call, in call-landing
  /// order — the observable proof that [KeryxRadioHost.tune]'s
  /// serialization actually holds calls to strict submission order rather
  /// than merely completing them all eventually.


  /// Consumed exactly once by the very next [rememberChannel] call — lets
  /// a test force a real suspension inside one `tune()` call so a second,
  /// unawaited `tune()` call has every opportunity to race ahead if
  /// [KeryxRadioHost.tune] were not actually serializing.


  void Function(RadioState? previous, RadioState next)? _radioStateListener;
  void Function(KeryxSettings settings)? _settingsListener;

  SessionHost sessionFactory({
    required String localPeerId,
    required String callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
  }) {
    final host = _FakeSessionHost(label: '${sessions.length}');
    sessions.add(host);
    return host;
  }

  Future<AudioSink> audioSinkFactory() async => sink;

  Future<void> audioSinkDisposer(AudioSink s) async {
    audioSinkDisposed = true;
  }

  Future<DeviceIdentity> identityFactory() async {
    identityFactoryCalls++;
    return DeviceIdentity(
      installUuid: 'test-install-uuid',
      peerId: 'test-peer-id',
      callsign: Callsign.parse('TEST-1'));
  }

  FacePermissionGate permissionGateFactory() =>
      _FakePermissionGate()..microphoneOutcome = micOutcome;

  RadioServiceController radioServiceFactory() {
    final platform = FakeRadioServicePlatform();
    servicePlatforms.add(platform);
    final controller = ChannelRadioServiceController(platform: platform);
    serviceControllers.add(controller);
    return controller;
  }

  Future<KeryxSettings> loadSettings() async => settings;

  void dispatch(RadioEvent event) {
    final previous = state;
    state = const RadioReducer().reduce(state, event);
    dispatched.add(event);
    // Mirrors Riverpod's own synchronous listener notification on state
    // change — `ref.listenManual`'s callback fires synchronously from
    // inside `notifier.state = ...`, which is exactly what
    // `KeryxRadioHost._syncServicePhase` depends on to stay in lockstep
    // with every dispatch.
    _radioStateListener?.call(previous, state);
  }

  RadioState readRadioState() => state;

  RadioHostUnsubscribe listenRadioState(
    void Function(RadioState? previous, RadioState next) onChange, {
    bool fireImmediately = false,
  }) {
    _radioStateListener = onChange;
    if (fireImmediately) onChange(null, state);
    return () => _radioStateListener = null;
  }

  RadioHostUnsubscribe listenSettings(
    void Function(KeryxSettings settings) onChange) {
    _settingsListener = onChange;
    return () => _settingsListener = null;
  }

  /// Simulates a settings-provider emission (what `SettingsController.save`
  /// would trigger in production, relayed by `FaceScreen`'s
  /// `listenSettings` bridge).
  void emitSettings(KeryxSettings next) {
    settings = next;
    _settingsListener?.call(next);
  }

  KeryxRadioHost build() => KeryxRadioHost(
    sessionFactory: sessionFactory,
    audioSinkFactory: audioSinkFactory,
    audioSinkDisposer: audioSinkDisposer,
    identityFactory: identityFactory,
    permissionGateFactory: permissionGateFactory,
    radioServiceFactory: radioServiceFactory,
    loadSettings: loadSettings,
    dispatch: dispatch,
    readRadioState: readRadioState,
    listenRadioState: listenRadioState,
    listenSettings: listenSettings,
  );
}

void main() {
  group('boot', () {
    test('constructs exactly one session/floor engine/sfx pipeline/service '
        'controller and reaches idle when mic is granted', () async {
      final harness = _Harness();
      final host = harness.build();

      await host.start();

      expect(harness.sessions, hasLength(1));
      expect(harness.sessions.single.startCalled, isTrue);
      expect(harness.serviceControllers, hasLength(1));
      expect(harness.state.phase, RadioPhase.idle);
      expect(host.current.floorEngine, same(harness.sessions.single.floorEngine));
      expect(host.current.micPermissionDenied, isFalse);

      await host.dispose();
    });

    test('mic denied: never dispatches BootCompleted, radio stays in boot, '
        'snapshot reports the denial', () async {
      final harness = _Harness()..micOutcome = FacePermissionOutcome.denied;
      final host = harness.build();

      await host.start();

      expect(harness.state.phase, RadioPhase.boot);
      expect(host.current.micPermissionDenied, isTrue);

      await host.dispose();
    });

    test('start() is idempotent: a second call while the first is in flight '
        'shares the same boot and constructs exactly one session '
        '(Verification VT-001)', () async {
      final harness = _Harness();
      final host = harness.build();

      final first = host.start();
      final second = host.start();
      expect(identical(first, second), isTrue);
      await Future.wait(<Future<void>>[first, second]);

      expect(harness.sessions, hasLength(1));
      expect(harness.serviceControllers, hasLength(1));

      await host.dispose();
    });
  });

  group('boot race / session reconstruction (Verification VT-002)', () {
    test('two overlapping session-affecting settings changes fired without '
        'awaiting between them leave exactly one live, undisposed session, '
        'matching whichever call actually lands', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      expect(harness.sessions, hasLength(1));
      final original = harness.sessions.single;

      // Two session-affecting changes, fired back-to-back with no await
      // between them — both `_maybeRebuildSession` calls race into
      // `_startSession` while the first is still suspended (real
      // asynchrony: `_stationsSub?.cancel()`/`session.start()` are both
      // genuine suspension points on `_FakeSessionHost`'s async methods).
      // Without the generation guard, the first call's session and
      // subscriptions would never be disposed. Mirrors
      // `face_screen_test.dart`'s own equivalent
      // "`_startSession` re-entrancy" test.
      final firstApply = host.applySettings(
        harness.settings.copyWith(totSeconds: 90));
      final secondApply = host.applySettings(
        harness.settings.copyWith(totSeconds: 100));
      await Future.wait(<Future<void>>[firstApply, secondApply]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The original boot session and every intermediate session raced out
      // by the two overlapping calls must all be disposed — exactly one
      // (the winner, whichever call's generation lands last) survives,
      // and it is the one `current.floorEngine` actually points at
      // (Technical §4: "A stale completion must not adopt an obsolete
      // session"; "no leaked superseded resources").
      expect(original.disposeCalled, isTrue);
      final undisposed = harness.sessions.where((s) => !s.disposeCalled);
      expect(undisposed, hasLength(1));
      expect(host.current.floorEngine, same(undisposed.single.floorEngine));

      await host.dispose();
    });

    test('a non-session-affecting settings change does not rebuild the '
        'session', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      expect(harness.sessions, hasLength(1));

      await host.applySettings(harness.settings.copyWith(squelchLevel: 9));

      expect(harness.sessions, hasLength(1));

      await host.dispose();
    });
  });

  group('disposal (Verification VT-004)', () {
    test('releases every subscription, timer, session and audio resource; '
        'repeated disposal is safe', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      final session = harness.sessions.single;

      await host.dispose();

      expect(session.disposeCalled, isTrue);
      expect(harness.audioSinkDisposed, isTrue);

      // Repeated disposal must not throw and must not re-run teardown.
      await host.dispose();
    });

    test('no hot mic: dispose() releases an in-progress local transmit '
        'before tearing anything down', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      host.pressPtt();
      expect(harness.sessions.single.floorEngine.isTransmitting, isTrue);

      await host.dispose();

      expect(harness.sessions.single.floorEngine.isTransmitting, isFalse);
    });

    test('no hot mic: a RadioServiceKilled event releases an in-progress '
        'local transmit and dispatches the honest off state', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      host.pressPtt();
      final engine = harness.sessions.single.floorEngine;
      expect(engine.isTransmitting, isTrue);

      harness.servicePlatforms.single.emit(const RadioServiceKilled());
      await Future<void>.delayed(Duration.zero);

      expect(engine.isTransmitting, isFalse);
      expect(harness.state.phase, RadioPhase.off);

      await host.dispose();
    });

    test('no hot mic: powerOff() releases an in-progress local transmit, '
        'dispatches PowerOff, and stops a running service', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      host.pressPtt();
      final engine = harness.sessions.single.floorEngine;
      expect(engine.isTransmitting, isTrue);
      expect(harness.serviceControllers.single.isRunning, isTrue);

      await host.powerOff();

      expect(engine.isTransmitting, isFalse);
      expect(harness.state.phase, RadioPhase.off);
      expect(harness.serviceControllers.single.isRunning, isFalse);

      await host.dispose();
    });
  });

  group('PTT', () {
    test('pressPtt/releasePtt/releaseLatch forward straight to the '
        "authoritative FloorEngine — never synthesize a granted/denied "
        'result themselves (Technical §5.1)', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      final engine = harness.sessions.single.floorEngine;

      host.pressPtt();
      expect(engine.isTransmitting, isTrue);

      host.releasePtt();
      expect(engine.isTransmitting, isFalse);

      host.pressPtt();
      expect(engine.isTransmitting, isTrue);
      host.releaseLatch();
      expect(engine.isTransmitting, isFalse);

      await host.dispose();
    });
  });
}
