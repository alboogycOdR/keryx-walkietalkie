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
import 'package:keryx/services/session/session.dart'
    show SessionEstablishmentFailure, StationInfo;

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

/// TASK-097: a [SessionHost] whose [start] never resolves — simulates the
/// field-reported hang (unreachable LAN peer/relay, or a hung platform
/// call) directly at the `SessionHost` abstraction `KeryxRadioHost` actually
/// depends on, independent of whatever bound a real
/// `RadioSessionController` gives itself. Proves `KeryxRadioHost`'s own
/// outer bound in `_startSession` fires even for a `SessionHost`
/// implementation that does not self-bound.
class _HangingSessionHost implements SessionHost {
  final _stations = StreamController<List<StationInfo>>.broadcast();

  bool disposeCalled = false;

  @override
  Stream<List<StationInfo>> get stations => _stations.stream;

  @override
  FloorEngine get floorEngine =>
      throw StateError('_HangingSessionHost never completes start()');

  @override
  Future<void> start() => Completer<void>().future;

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    await _stations.close();
  }
}

/// TASK-100: a [SessionHost] whose [start] throws the real controller's own
/// typed [SessionEstablishmentFailure] naming a specific [transport] —
/// proves `KeryxRadioHost` attributes `sessionFailureKind` from the typed
/// exception rather than from the settings-derived guess, e.g. a LOCAL
/// no-target-boot failure on a relay-configured device must not be
/// mislabelled "linked".
class _ThrowingSessionHost implements SessionHost {
  _ThrowingSessionHost(this.transport);

  final Transport transport;
  bool disposeCalled = false;

  @override
  Stream<List<StationInfo>> get stations => const Stream.empty();

  @override
  FloorEngine get floorEngine =>
      throw StateError('_ThrowingSessionHost never completes start()');

  @override
  Future<void> start() => Future<void>.error(
    SessionEstablishmentFailure(transport, StateError('boom'), StackTrace.current));

  @override
  Future<void> dispose() async {
    disposeCalled = true;
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
  final List<_HangingSessionHost> hangingSessions = <_HangingSessionHost>[];
  final RecordingAudioSink sink = RecordingAudioSink();
  final List<FakeRadioServicePlatform> servicePlatforms =
      <FakeRadioServicePlatform>[];
  final List<ChannelRadioServiceController> serviceControllers =
      <ChannelRadioServiceController>[];

  bool audioSinkDisposed = false;
  int identityFactoryCalls = 0;
  FacePermissionOutcome micOutcome = FacePermissionOutcome.granted;

  /// TASK-097: when true, [sessionFactory] hands out a [_HangingSessionHost]
  /// (never resolves `start()`) instead of the normal [_FakeSessionHost] —
  /// lets a test flip real recovery back on mid-test (set back to `false`
  /// before a later `applySettings`/rebuild) without rebuilding the harness.
  bool hangSessions = false;

  /// TASK-100: when non-null, [sessionFactory] hands out a
  /// [_ThrowingSessionHost] that throws a typed [SessionEstablishmentFailure]
  /// naming this transport, instead of the normal [_FakeSessionHost].
  Transport? throwTypedFailure;

  /// Ordered log of the two lifecycle events whose *relative order* is the
  /// v2 enrolment contract: `'enrolment:start'`/`'enrolment:done'` around
  /// [enrolment], `'session'` when [sessionFactory] is invoked.
  final List<String> events = <String>[];

  /// The injected [RadioDirectoryEnrolment]. Default resolves immediately;
  /// a test swaps in a throwing/hanging one to prove best-effort + bound.
  Future<void> Function() enrolment = () async {};

  int enrolmentCalls = 0;

  Future<void> _ensureDirectoryEnrolment() async {
    enrolmentCalls++;
    events.add('enrolment:start');
    await enrolment();
    events.add('enrolment:done');
  }

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
    events.add('session');
    if (hangSessions) {
      final host = _HangingSessionHost();
      hangingSessions.add(host);
      return host;
    }
    final typedFailureTransport = throwTypedFailure;
    if (typedFailureTransport != null) {
      return _ThrowingSessionHost(typedFailureTransport);
    }
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

  KeryxRadioHost build({
    Duration sessionStartTimeout = const Duration(seconds: 25),
  }) => KeryxRadioHost(
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
    ensureDirectoryEnrolment: _ensureDirectoryEnrolment,
    sessionStartTimeout: sessionStartTimeout,
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

  // TASK-097: `RadioHost.start()`'s boot sequence previously had no bound
  // on session establishment — a stalled `session.start()` left
  // `RadioPhase.boot` forever with nothing surfaced. See
  // `dossiers/TASK-097.md` for the field report this traces to.
  group('session-establishment bound (TASK-097)', () {
    test(
      'a never-resolving session.start() does not hang boot forever — '
      'BootCompleted still dispatches, phase leaves boot, and the '
      'snapshot names which transport failed',
      () async {
        final harness = _Harness()..hangSessions = true;
        final host = harness.build(
          sessionStartTimeout: const Duration(milliseconds: 50));

        await host.start();

        expect(harness.state.phase, isNot(RadioPhase.boot));
        expect(harness.state.phase, RadioPhase.idle);
        expect(host.current.sessionFailureKind, SessionFailureKind.local);
        expect(host.current.floorEngine, isNull);
        expect(host.current.micPermissionDenied, isFalse);
        expect(harness.hangingSessions, hasLength(1));
        expect(harness.hangingSessions.single.disposeCalled, isTrue);

        await host.dispose();
      },
      timeout: const Timeout(Duration(seconds: 5)));

    test(
      'the failure kind names LINKED when the settings snapshot has a '
      'relay configured',
      () async {
        final harness = _Harness()
          ..settings = const KeryxSettings(relayUrl: 'wss://relay.example')
          ..hangSessions = true;
        final host = harness.build(
          sessionStartTimeout: const Duration(milliseconds: 50));

        await host.start();

        expect(host.current.sessionFailureKind, SessionFailureKind.linked);

        await host.dispose();
      },
      timeout: const Timeout(Duration(seconds: 5)));

    test(
      'TASK-100: a LOCAL typed SessionEstablishmentFailure is attributed '
      'from the exception itself, not the settings guess — a relay-'
      'configured device whose (LOCAL, no-target-boot) session throws must '
      'read local, not linked',
      () async {
        final harness = _Harness()
          ..settings = const KeryxSettings(relayUrl: 'wss://relay.example')
          ..throwTypedFailure = Transport.direct;
        final host = harness.build();

        await host.start();

        expect(host.current.sessionFailureKind, SessionFailureKind.local);

        await host.dispose();
      });

    test(
      'TASK-100: a LINKED typed SessionEstablishmentFailure is attributed '
      'from the exception itself even when settings would have guessed '
      'local',
      () async {
        final harness = _Harness()
          ..settings = const KeryxSettings(relayUrl: '')
          ..throwTypedFailure = Transport.relay;
        final host = harness.build();

        await host.start();

        expect(host.current.sessionFailureKind, SessionFailureKind.linked);

        await host.dispose();
      });

    test(
      'PTT stays inert while a session-establishment failure is active — '
      'floorEngine remains null so pressPtt/releasePtt/releaseLatch are '
      'safe no-ops (mirrors talk_screen.dart\'s ptteEnabled gate on '
      'floorEngine != null; Technical §5.1)',
      () async {
        final harness = _Harness()..hangSessions = true;
        final host = harness.build(
          sessionStartTimeout: const Duration(milliseconds: 50));

        await host.start();
        expect(host.current.floorEngine, isNull);

        host.pressPtt();
        host.releasePtt();
        host.releaseLatch();

        await host.dispose();
      },
      timeout: const Timeout(Duration(seconds: 5)));

    test(
      'mic-permission-denied stays a distinct, unaffected failure mode — '
      'sessionFailureKind stays null and the radio still never leaves '
      'boot for that reason alone (existing TASK-038 behavior unmodified)',
      () async {
        final harness = _Harness()
          ..micOutcome = FacePermissionOutcome.denied;
        final host = harness.build();

        await host.start();

        expect(harness.state.phase, RadioPhase.boot);
        expect(host.current.micPermissionDenied, isTrue);
        expect(host.current.sessionFailureKind, isNull);

        await host.dispose();
      });

    test(
      'a subsequent successful session start clears a prior '
      'sessionFailureKind — never sticky once the underlying problem '
      'clears',
      () async {
        final harness = _Harness()..hangSessions = true;
        final host = harness.build(
          sessionStartTimeout: const Duration(milliseconds: 50));

        await host.start();
        expect(host.current.sessionFailureKind, isNotNull);

        harness.hangSessions = false;
        await host.applySettings(
          harness.settings.copyWith(totSeconds: 90));

        expect(host.current.sessionFailureKind, isNull);
        expect(host.current.floorEngine, isNotNull);
        expect(harness.sessions, hasLength(1));

        await host.dispose();
      },
      timeout: const Timeout(Duration(seconds: 5)));
  });

  // v2 Technical §6.4: "load identity → open directory session → … → start
  // RadioSessionController". The host owns the ORDER (enrolment strictly
  // before any session start, on boot and on every rebuild) and the
  // degradation rules (best-effort, bounded) — the composition root owns
  // what enrolment actually does. `test/app_shell/directory_enrolment_test
  // .dart` proves the real enrolment feeds this seam end to end.
  group('directory enrolment ordering (v2 §6.4)', () {
    test('boot awaits enrolment to completion before the session factory '
        'is ever invoked', () async {
      final gate = Completer<void>();
      final harness = _Harness()..enrolment = () => gate.future;
      final host = harness.build();

      final boot = host.start();
      // Let boot run up to the enrolment await: identity, settings,
      // permissions, audio sink, service start all resolve on microtasks.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(harness.events, ['enrolment:start']);
      expect(harness.sessions, isEmpty,
          reason: 'no session may start while enrolment is still pending');

      gate.complete();
      await boot;

      expect(harness.events, ['enrolment:start', 'enrolment:done', 'session']);
      expect(harness.state.phase, RadioPhase.idle);
      await host.dispose();
    });

    test('a settings-triggered rebuild re-awaits enrolment before starting '
        'the replacement session', () async {
      final harness = _Harness();
      final host = harness.build();
      await host.start();
      expect(harness.enrolmentCalls, 1);

      await host.applySettings(
          harness.settings.copyWith(relayUrl: 'wss://relay.example/ws'));

      expect(harness.enrolmentCalls, 2);
      expect(harness.events, [
        'enrolment:start', 'enrolment:done', 'session',
        'enrolment:start', 'enrolment:done', 'session',
      ]);
      expect(harness.sessions, hasLength(2));
      await host.dispose();
    });

    test('a throwing enrolment is best-effort: the session still starts and '
        'boot still reaches idle', () async {
      final harness = _Harness()
        ..enrolment = () async => throw StateError('directory down');
      final host = harness.build();

      await host.start();

      expect(harness.events, ['enrolment:start', 'session'],
          reason: 'the throw skips enrolment:done but never the session');
      expect(harness.sessions.single.startCalled, isTrue);
      expect(harness.state.phase, RadioPhase.idle);
      expect(host.current.sessionFailureKind, isNull,
          reason: 'an enrolment failure is not a session failure');
      await host.dispose();
    });

    test('a hanging enrolment is bounded by sessionStartTimeout — boot '
        'proceeds instead of hanging forever', () async {
      final harness = _Harness()..enrolment = () => Completer<void>().future;
      final host = harness.build(
          sessionStartTimeout: const Duration(milliseconds: 50));

      await host.start();

      expect(harness.events, ['enrolment:start', 'session']);
      expect(harness.sessions.single.startCalled, isTrue);
      expect(harness.state.phase, RadioPhase.idle);
      await host.dispose();
    }, timeout: const Timeout(Duration(seconds: 5)));

    test('a host built without an enrolment seam boots exactly as before '
        '(no-op default)', () async {
      final harness = _Harness();
      final host = KeryxRadioHost(
        sessionFactory: harness.sessionFactory,
        audioSinkFactory: harness.audioSinkFactory,
        audioSinkDisposer: harness.audioSinkDisposer,
        identityFactory: harness.identityFactory,
        permissionGateFactory: harness.permissionGateFactory,
        radioServiceFactory: harness.radioServiceFactory,
        loadSettings: harness.loadSettings,
        dispatch: harness.dispatch,
        readRadioState: harness.readRadioState,
        listenRadioState: harness.listenRadioState,
        listenSettings: harness.listenSettings,
      );

      await host.start();

      expect(harness.enrolmentCalls, 0);
      expect(harness.events, ['session']);
      expect(harness.state.phase, RadioPhase.idle);
      await host.dispose();
    });
  });
}
