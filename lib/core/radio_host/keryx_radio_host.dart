import 'dart:async';
import 'dart:developer' as developer;

import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;
import 'package:keryx/services/sound/sound.dart';

import 'permission_gate.dart';
import 'radio_host_contract.dart';
import 'radio_host_snapshot.dart';
import 'session_host.dart';

/// Cancels a subscription registered via [ListenRadioState]/[ListenSettings].
typedef RadioHostUnsubscribe = void Function();

/// The exact factory shape `FaceScreen` has injected since TASK-037/038 —
/// unchanged, so its existing default (a real `RadioSessionController`
/// wrapped in `RadioSessionHostAdapter`) and every test double already
/// written against it keep working verbatim.
typedef RadioSessionFactory =
    SessionHost Function({
      required String localPeerId,
      required String callsign,
      required KeryxSettings settings,
      required void Function(RadioEvent event) dispatch,
    });

typedef RadioAudioSinkFactory = Future<AudioSink> Function();
typedef RadioAudioSinkDisposer = Future<void> Function(AudioSink sink);
typedef RadioIdentityFactory = Future<DeviceIdentity> Function();
typedef RadioPermissionGateFactory = FacePermissionGate Function();
typedef RadioServiceFactory = RadioServiceController Function();

/// Riverpod bridge callbacks — see `radio_host.dart`'s library dartdoc for
/// why this module takes plain callbacks instead of a `Ref`/`WidgetRef`.
typedef LoadSettings = Future<KeryxSettings> Function();
typedef DispatchRadioEvent = void Function(RadioEvent event);
typedef ReadRadioState = RadioState Function();

/// Registers a listener and returns the function that cancels it. Called
/// exactly once, from [KeryxRadioHost.start]. `fireImmediately: true`
/// mirrors `Riverpod`'s own `ref.listenManual(..., fireImmediately: true)`
/// — the callback fires synchronously on registration with `previous ==
/// null`, establishing [SfxProjection]'s edge-detection baseline before
/// `PowerOn` is dispatched.
typedef ListenRadioState =
    RadioHostUnsubscribe Function(
      void Function(RadioState? previous, RadioState next) onChange, {
      bool fireImmediately,
    });

typedef ListenSettings =
    RadioHostUnsubscribe Function(void Function(KeryxSettings settings) onChange);

/// Production [RadioHost]: the block hoisted out of `_FaceScreenState`
/// (Technical §1.1 / ADR-001 §6), unchanged in substance. See
/// `radio_host.dart`'s library dartdoc for the module-level design notes.
class KeryxRadioHost implements RadioHost {
  KeryxRadioHost({
    required this.sessionFactory,
    required this.audioSinkFactory,
    required this.audioSinkDisposer,
    required this.identityFactory,
    required this.permissionGateFactory,
    required this.radioServiceFactory,
    required this.loadSettings,
    required this.dispatch,
    required this.readRadioState,
    required this.listenRadioState,
    required this.listenSettings,
  });

  final RadioSessionFactory sessionFactory;
  final RadioAudioSinkFactory audioSinkFactory;
  final RadioAudioSinkDisposer audioSinkDisposer;
  final RadioIdentityFactory identityFactory;
  final RadioPermissionGateFactory permissionGateFactory;
  final RadioServiceFactory radioServiceFactory;
  final LoadSettings loadSettings;
  final DispatchRadioEvent dispatch;
  final ReadRadioState readRadioState;
  final ListenRadioState listenRadioState;
  final ListenSettings listenSettings;

  static const String _serviceFaultLabel = 'SVC FAULT';
  static const String _logName = 'RadioHost';

  // --- lifecycle bookkeeping ---------------------------------------------

  bool _disposed = false;
  Future<void>? _startFuture;

  /// Review round-1 (pre-hoist) finding (d), preserved: guards session
  /// (re)construction against re-entrancy. See [_startSession]'s dartdoc.
  int _sessionGeneration = 0;

  // --- owned resources -----------------------------------------------

  DeviceIdentity? _identity;
  SessionHost? _session;
  FloorEngine? _floorEngine;
  SfxEngine? _sfxEngine;
  SfxProjection? _sfxProjection;
  AudioSink? _audioSink;
  RadioServiceController? _radioService;

  /// The settings snapshot the currently-active [_session] was built from
  /// — compared against every [applySettings] call to decide whether a
  /// rebuild is warranted. See [_maybeRebuildSession]'s dartdoc.
  KeryxSettings? _appliedSettings;

  RadioHostUnsubscribe? _radioStateUnsub;
  RadioHostUnsubscribe? _settingsUnsub;
  StreamSubscription<List<StationInfo>>? _stationsSub;
  StreamSubscription<FloorEffect>? _floorEffectsSub;
  StreamSubscription<RadioServiceEvent>? _radioServiceSub;
  StreamSubscription<MeterLevel>? _meterLevelSub;

  /// Last [RadioTransportPhase] actually pushed to [_radioService] — de-
  /// dupes [_syncServicePhase] so an unrelated [RadioState] emission
  /// doesn't re-issue an identical `setPhase` call.
  RadioTransportPhase? _lastServicePhase;

  final StreamController<RadioState> _radioStateStream =
      StreamController<RadioState>.broadcast();
  final StreamController<FloorEffect> _floorEffectsProxy =
      StreamController<FloorEffect>.broadcast();
  final StreamController<KeryxSettings> _settingsStream =
      StreamController<KeryxSettings>.broadcast();

  Timer? _sfxTick;

  // --- snapshot / current-state access ------------------------------------

  bool _micPermissionDenied = false;
  String? _serviceFaultMessage;
  List<StationInfo> _stations = const <StationInfo>[];
  MeterLevel _meterLevel = MeterLevel.decorative;

  RadioHostSnapshot _snapshot = const RadioHostSnapshot();
  final StreamController<RadioHostSnapshot> _changes =
      StreamController<RadioHostSnapshot>.broadcast();

  @override
  RadioHostSnapshot get current => _snapshot;

  @override
  Stream<RadioHostSnapshot> get changes => _changes.stream;

  void _emitSnapshot() {
    _snapshot = RadioHostSnapshot(
      micPermissionDenied: _micPermissionDenied,
      serviceFaultMessage: _serviceFaultMessage,
      floorEngine: _floorEngine,
      stations: _stations,
      meterLevel: _meterLevel,
    );
    if (!_changes.isClosed) _changes.add(_snapshot);
  }

  void _log(String message) =>
      developer.log(message, name: _logName);

  // --- start ---------------------------------------------------------

  @override
  Future<void> start() {
    // Technical §4: "A single boot operation is in flight; concurrent
    // boots share or serialize its result." A second caller while the
    // first `start()` is still running gets the exact same `Future`
    // rather than re-running `_bootInternal` (which would double-construct
    // every owned resource this class exists to own exactly one of).
    final inFlight = _startFuture;
    if (inFlight != null) return inFlight;
    final future = _bootInternal();
    _startFuture = future;
    return future;
  }

  Future<void> _bootInternal() async {
    if (_disposed) return;
    final identity = await identityFactory();
    if (_disposed) return;
    final settings = await loadSettings();
    if (_disposed) return;

    // TASK-038 permissions (TS L368, KRX-092). RECORD_AUDIO is blocking —
    // the radio cannot transmit without it, so `_micPermissionDenied`
    // gates `BootCompleted` below (radio stays in `boot`, never reaches
    // `idle`). POST_NOTIFICATIONS / NEARBY_WIFI_DEVICES are non-blocking
    // (API 33+ only). Review round-1 (pre-hoist) finding (a): these two
    // MUST stay sequential, never `Future.wait`-ed — `permission_handler`'s
    // Android side rejects an overlapping `.request()` outright.
    final permissionGate = permissionGateFactory();
    final micOutcome = await _safeEnsurePermission(
      permissionGate.ensureMicrophone,
      label: 'microphone',
    );
    if (_disposed) return;
    final micDenied = micOutcome == FacePermissionOutcome.denied;
    _micPermissionDenied = micDenied;
    _emitSnapshot();

    await _safeEnsurePermission(
      permissionGate.ensureNotifications,
      label: 'notifications',
    );
    if (_disposed) return;
    await _safeEnsurePermission(
      permissionGate.ensureNearbyWifiDevices,
      label: 'nearby Wi-Fi devices',
    );
    if (_disposed) return;

    final sink = await audioSinkFactory();
    if (_disposed) {
      unawaited(audioSinkDisposer(sink));
      return;
    }

    final sfxEngine = SfxEngine(sink: sink);
    final sfxProjection = SfxProjection(
      engine: sfxEngine,
      states: _radioStateStream.stream,
      floorEffects: _floorEffectsProxy.stream,
      settings: _settingsStream.stream,
      initialSettings: settings,
    );

    if (_disposed) {
      unawaited(sfxProjection.dispose());
      sfxEngine.dispose();
      unawaited(audioSinkDisposer(sink));
      return;
    }

    _identity = identity;
    _audioSink = sink;
    _sfxEngine = sfxEngine;
    _sfxProjection = sfxProjection;
    _emitSnapshot();

    _sfxTick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_disposed) _sfxProjection?.tick();
    });

    // `fireImmediately: true` pushes the current (still `off`) state into
    // `_radioStateStream` synchronously, right now — before `PowerOn`
    // below — establishing `SfxProjection`'s edge-detection baseline.
    _radioStateUnsub = listenRadioState((previous, next) {
      if (!_radioStateStream.isClosed) _radioStateStream.add(next);
      unawaited(_syncServicePhase(next));
    }, fireImmediately: true);

    _settingsUnsub = listenSettings((changedSettings) {
      unawaited(applySettings(changedSettings));
    });

    dispatch(const PowerOn());

    final initial = readRadioState();

    final radioService = radioServiceFactory();
    _radioServiceSub = radioService.events.listen(_onRadioServiceEvent);
    try {
      await radioService.start(
        channelLabel: _notificationLabel(initial),
      );
    } catch (error, stack) {
      // TASK-038 acceptance criterion: a `start()` fault degrades
      // gracefully — the radio keeps working foregrounded, this is a
      // telltale only, never a crash.
      _log('radio service start failed: $error\n$stack');
      _serviceFaultMessage = _serviceFaultLabel;
      _emitSnapshot();
    }
    if (_disposed) {
      unawaited(radioService.dispose());
      return;
    }
    _radioService = radioService;

    await _startSession(
      identity: identity,
      settings: settings,
    );
    if (_disposed) return;

    // Denied mic: never reach `idle` (TASK-038 acceptance criterion) — a
    // presentation-layer telltale stands in for the radio being usable.
    if (!micDenied) {
      dispatch(const BootCompleted());
    }
  }

  Future<FacePermissionOutcome> _safeEnsurePermission(
    Future<FacePermissionOutcome> Function() ensure, {
    required String label,
  }) async {
    try {
      return await ensure();
    } catch (error, stack) {
      _log('$label permission check failed: $error\n$stack');
      return FacePermissionOutcome.denied;
    }
  }

  String _notificationLabel(RadioState state) {
    final roomId = state.roomId;
    if (roomId == null || roomId.isEmpty) return 'KERYX';
    return roomId.length <= 8 ? roomId : roomId.substring(0, 8);
  }

  // --- session (re)construction ----------------------------------------

  /// (Re)builds the active [SessionHost]. Called once from [_bootInternal]
  /// and again from [_maybeRebuildSession] on a session-affecting settings
  /// change. Tears down whatever
  /// session/subscriptions are currently active first — safe to call with
  /// `_session == null` (the first-boot case).
  ///
  /// **Re-entrancy (review round-1 (pre-hoist) finding (d), preserved).**
  /// `session.start()` is a real suspension point (LOCAL binds UDP sockets
  /// and runs discovery), so two overlapping calls are possible whenever
  /// two session-affecting settings fields change close together.
  /// [_sessionGeneration] is captured on entry and re-checked after the
  /// `await`: a call that resumes to find a newer call already in flight
  /// (or already landed) disposes the session it just started instead of
  /// adopting it — Verification VT-002's exact requirement.
  Future<void> _startSession({
    required DeviceIdentity identity,
    required KeryxSettings settings,
  }) async {
    final myGeneration = ++_sessionGeneration;
    final previousSession = _session;
    await _stationsSub?.cancel();
    _stationsSub = null;
    await _floorEffectsSub?.cancel();
    _floorEffectsSub = null;
    await _meterLevelSub?.cancel();
    _meterLevelSub = null;
    _meterLevel = MeterLevel.decorative;
    if (previousSession != null) {
      unawaited(
        previousSession.dispose().catchError(
          (Object error, StackTrace stack) =>
              _log('previous session dispose failed: $error\n$stack'),
        ),
      );
    }
    _stations = const <StationInfo>[];
    _session = null;
    _floorEngine = null;
    _emitSnapshot();

    final session = sessionFactory(
      localPeerId: identity.peerId,
      callsign: identity.callsign.value,
      settings: settings,
      dispatch: dispatch,
    );
    await session.start();
    if (_disposed || myGeneration != _sessionGeneration) {
      // Torn down, or superseded by a newer `_startSession` call that
      // arrived while this one was suspended in `session.start()` —
      // either way this session must not become `_session`. Dispose it
      // rather than leak its transport/sockets.
      unawaited(session.dispose());
      return;
    }

    _appliedSettings = settings;
    _floorEffectsSub = session.floorEngine.effects.listen((effect) {
      if (!_floorEffectsProxy.isClosed) _floorEffectsProxy.add(effect);
    });
    _stationsSub = session.stations.listen((stations) {
      _stations = stations;
      _emitSnapshot();
    });
    // `SessionHost` exposes `start`/`retune`/`dispose`/`floorEngine`/
    // `stations` — widening it for a
    // single telemetry field was rejected in favour of exactly this seam:
    // `RadioSessionHostAdapter.debugController` is already public
    // ("lets a production-path integration test reach into the composed
    // chain without widening `SessionHost` itself"). A hand-written
    // `SessionHost` test fake is simply not a `RadioSessionHostAdapter`, so
    // it falls through to the decorative default with no cast needed.
    if (session is RadioSessionHostAdapter) {
      final controller = session.debugController;
      _meterLevel = controller.meterLevel;
      _meterLevelSub = controller.meterLevelChanges.listen((level) {
        _meterLevel = level;
        _emitSnapshot();
      });
    }

    _session = session;
    _floorEngine = session.floorEngine;
    _emitSnapshot();
  }

  // --- settings --------------------------------------------------------

  @override
  Future<void> applySettings(KeryxSettings settings) async {
    if (_disposed) return;
    if (!_settingsStream.isClosed) _settingsStream.add(settings);
    await _maybeRebuildSession(settings);
  }

  /// **Disclosed decision (pre-hoist), preserved.** `RadioSessionController`
  /// treats settings as a construction-time snapshot, so "a settings
  /// change is observed without restart" is satisfied at this boundary by
  /// tearing down and reconstructing the session on the session-affecting
  /// subset of fields ([_sessionAffectingFieldsChanged]).
  Future<void> _maybeRebuildSession(KeryxSettings settings) async {
    if (_disposed) return;
    final identity = _identity;
    final applied = _appliedSettings;
    if (identity == null || applied == null) {
      return; // no session yet to rebuild (still booting)
    }
    if (!_sessionAffectingFieldsChanged(applied, settings)) {
      _appliedSettings = settings;
      return;
    }
    await _startSession(
      identity: identity,
      settings: settings,
    );
  }

  bool _sessionAffectingFieldsChanged(KeryxSettings a, KeryxSettings b) =>
      a.forceLocalOnly != b.forceLocalOnly ||
      a.relayUrl != b.relayUrl ||
      a.tokenServiceUrl != b.tokenServiceUrl ||
      a.totSeconds != b.totSeconds ||
      a.busyLockout != b.busyLockout;

  // --- PTT ---------------------------------------------------------------

  @override
  void pressPtt() => _floorEngine?.requestTransmit();

  @override
  void releasePtt() => _floorEngine?.releaseTransmit();

  @override
  void releaseLatch() => _floorEngine?.releaseTransmit();

  // --- power off -----------------------------------------------------

  @override
  Future<void> powerOff() async {
    if (_disposed) return;
    // No-hot-mic guarantee (Technical §4; PTS §8.5): release any local
    // transmit before anything else so a deliberate power-off can never
    // leave the mic hot even for one more effect cycle.
    _floorEngine?.releaseTransmit();
    dispatch(const PowerOff());
    final service = _radioService;
    if (service != null && service.isRunning) {
      try {
        await service.stop();
      } catch (error, stack) {
        _log('radio service stop failed: $error\n$stack');
      }
    }
  }

  // --- radio service events -----------------------------------------

  void _onRadioServiceEvent(RadioServiceEvent event) {
    switch (event) {
      case RadioServiceKilled():
        // TS §8.8 / FR-105: OEM/system killed the FGS without a user
        // power-off. `releaseTransmit` first is a hoist-scoped, disclosed
        // strengthening over the pre-hoist code (which only dispatched
        // `PowerOff`): this task's own acceptance criterion requires "a
        // service kill... leave no locally transmitting track", asserted
        // against the engine, not just the projected `RadioState`.
        _floorEngine?.releaseTransmit();
        dispatch(const PowerOff());
      case RadioServicePttAction():
        // Notification PTT is a click/toggle, not a press-and-hold — it
        // toggles around whatever the floor engine's own transmit state
        // currently is.
        final engine = _floorEngine;
        if (engine != null) {
          if (engine.isTransmitting) {
            engine.releaseTransmit();
          } else {
            engine.requestTransmit();
          }
        }
      case RadioServicePowerOffAction():
        // `ChannelRadioServiceController`'s own `_onEvent` already marks
        // itself not-running by the time Dart hears about this — calling
        // `.stop()` here would be a same-tick no-op. `releaseTransmit`
        // first for the same no-hot-mic reason as `RadioServiceKilled`.
        _floorEngine?.releaseTransmit();
        dispatch(const PowerOff());
      case RadioServiceFailed(:final message):
        // Graceful degrade: log + on-face telltale, never a crash. The
        // radio (session, floor, sound) keeps running exactly as it was.
        _log('radio service fault: $message');
        _serviceFaultMessage = _serviceFaultLabel;
        _emitSnapshot();
    }
  }

  /// Maps [RadioState.phase] to the native service's coarser
  /// [RadioTransportPhase] and pushes it through only on an actual change.
  /// A no-op before the service has started or after it has stopped.
  Future<void> _syncServicePhase(RadioState state) async {
    final service = _radioService;
    if (service == null || !service.isRunning) return;
    final phase = switch (state.phase) {
      RadioPhase.rxActive => RadioTransportPhase.rx,
      RadioPhase.tx || RadioPhase.txRequest => RadioTransportPhase.tx,
      _ => RadioTransportPhase.idle,
    };
    if (phase == _lastServicePhase) return;
    _lastServicePhase = phase;
    try {
      await service.setPhase(phase);
    } catch (error, stack) {
      _log('radio service setPhase failed: $error\n$stack');
    }
  }

  // --- disposal --------------------------------------------------------

  @override
  Future<void> dispose() async {
    // Verification VT-004: "Repeated disposal is safe."
    if (_disposed) return;
    _disposed = true;

    // No-hot-mic guarantee before any teardown (Technical §4; PTS §8.5).
    _floorEngine?.releaseTransmit();

    // Deliberately fire-and-forget (`unawaited`), never `await`, for every
    // step below — same shape as the pre-hoist `_FaceScreenState.dispose()`
    // (a plain synchronous `void dispose()` override). `dispose()` is
    // called from `State.dispose()`, which Flutter requires to run
    // synchronously; if this method suspended at an `await` before
    // reaching `_session?.dispose()`, the caller's `unawaited(host.dispose())`
    // would only run the synchronous prefix before this function yields,
    // deferring the actual `FloorEngine`/session teardown (and the timers
    // it cancels) to a later microtask that a test's final pump may never
    // flush — exactly the "Timer still pending after the widget tree was
    // disposed" failure this shape avoids. Every teardown call below still
    // runs its own synchronous prefix immediately, in order, within this
    // single synchronous call stack.
    _sfxTick?.cancel();
    _radioStateUnsub?.call();
    _settingsUnsub?.call();
    unawaited(_stationsSub?.cancel());
    unawaited(_floorEffectsSub?.cancel());
    unawaited(_radioServiceSub?.cancel());
    unawaited(_meterLevelSub?.cancel());
    unawaited(
      _sfxProjection?.dispose().catchError(
        (Object error, StackTrace stack) =>
            _log('sfxProjection dispose failed: $error\n$stack'),
      ),
    );
    _sfxEngine?.dispose();
    final sink = _audioSink;
    if (sink != null) unawaited(audioSinkDisposer(sink));
    unawaited(
      _session?.dispose().catchError(
        (Object error, StackTrace stack) =>
            _log('session dispose failed: $error\n$stack'),
      ),
    );
    unawaited(
      _radioService?.dispose().catchError(
        (Object error, StackTrace stack) =>
            _log('radioService dispose failed: $error\n$stack'),
      ),
    );
    unawaited(_radioStateStream.close());
    unawaited(_floorEffectsProxy.close());
    unawaited(_settingsStream.close());
    unawaited(_changes.close());
  }
}
