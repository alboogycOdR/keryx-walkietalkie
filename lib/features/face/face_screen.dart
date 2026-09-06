import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/event_qr/qr_export_screen.dart';
import 'package:keryx/features/event_qr/qr_scan_screen.dart';
import 'package:keryx/features/ptt/ptt.dart';
import 'package:keryx/features/settings_panel/back_panel_screen.dart';
import 'package:keryx/features/tuning/tuning.dart';
import 'package:keryx/services/platform/platform.dart'
    show
        ChannelRadioServiceController,
        RadioServiceController,
        RadioServiceEvent,
        RadioServiceFailed,
        RadioServiceKilled,
        RadioServicePowerOffAction,
        RadioServicePttAction,
        RadioTransportPhase;
import 'package:keryx/services/session/session.dart'
    show RadioSessionController, StationInfo;
import 'package:keryx/services/sound/sound.dart';

import 'amplitude_source.dart';
import 'face_view.dart';
import 'permission_gate.dart';
import 'roster.dart' as roster;
import 'roster_screen.dart';
import 'session_host.dart';

/// Boots identity + settings + the radio session (TASK-035's
/// `RadioSessionController`, LOCAL/AUTO/LINKED per settings), then renders
/// [FaceView] as a live projection of [radioStateProvider] — the app's
/// actual home screen.
///
/// This is the sole owner of the [SessionHost] instance (production default:
/// a real `RadioSessionController` wrapped by [RadioSessionHostAdapter] — see
/// `session_host.dart`'s dartdoc for why the adapter exists) and of the
/// [SfxEngine]/[SfxProjection] sound pipeline (TASK-033's [AudioSink]). No
/// other widget in `lib/features/face/**` touches `FloorEngine`,
/// `RadioStateController`, or the audio pipeline directly — [FaceView] only
/// ever receives values, never mutates them, per TS §8.2.
///
/// **Testability — constructor-injected factories.** `RadioSessionController
/// .start()` performs real I/O (real UDP sockets for LOCAL discovery/
/// signaling) and [DeviceAudioSink] needs a real SoLoud native backend,
/// neither of which can run inside `flutter test`. [sessionFactory] and
/// [audioSinkFactory] default to the real production paths (unchanged
/// behaviour for `const FaceScreen()` in `app.dart`), but a test can
/// construct `FaceScreen(sessionFactory: ..., audioSinkFactory: ...)` with
/// fakes — see `session_host.dart` for the interface a fake implements.
class FaceScreen extends ConsumerStatefulWidget {
  const FaceScreen({
    super.key,
    this.sessionFactory = _defaultSessionFactory,
    this.audioSinkFactory = _defaultAudioSinkFactory,
    this.audioSinkDisposer = _defaultAudioSinkDisposer,
    this.identityFactory = _defaultIdentityFactory,
    this.permissionGateFactory = _defaultPermissionGateFactory,
    this.radioServiceFactory = _defaultRadioServiceFactory,
  });

  final SessionHost Function({
    required String localPeerId,
    required String callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
    required int initialChannel,
    required int initialCode,
  })
  sessionFactory;

  final Future<AudioSink> Function() audioSinkFactory;

  /// Paired with [audioSinkFactory] rather than assumed: [AudioSink] the
  /// abstract interface has no `dispose()` of its own (only the concrete
  /// [DeviceAudioSink] does; `RecordingAudioSink`, the test double, needs
  /// none), so disposal has to be a matching injected function rather than
  /// a call through the interface. The default checks the runtime type,
  /// which keeps production behaviour a plain no-arg swap for tests without
  /// requiring every test to also inject a disposer.
  final Future<void> Function(AudioSink sink) audioSinkDisposer;

  /// `IdentityRepository(SecureIdentityStore())` (`lib/core/identity/**`,
  /// out of this task's `Owned_Paths`) resolves over a real secure-storage
  /// platform channel that, on this project's `flutter test` host, never
  /// answers (no plugin implementation registered — it just hangs
  /// indefinitely rather than throwing). That is orthogonal to the
  /// session/audio testability problem this file otherwise solves, but it
  /// blocks `_boot` just the same, so it gets the identical
  /// constructor-injected-factory treatment: production default is
  /// unchanged, a test can substitute a synchronous fake identity.
  final Future<DeviceIdentity> Function() identityFactory;

  /// TASK-038: `permission_handler`'s real plugin is a platform channel with
  /// no registered implementation under `flutter test` — same story as
  /// [identityFactory]. Production default wraps `DeviceFacePermissionGate`
  /// (see `permission_gate.dart`); tests inject a fake gate that never
  /// touches a real platform channel.
  final FacePermissionGate Function() permissionGateFactory;

  /// TASK-038: the Android radio foreground service (KRX-080). Production
  /// default is `ChannelRadioServiceController.production()`; tests inject
  /// `ChannelRadioServiceController(platform: FakeRadioServicePlatform())`
  /// — that fake already lives in `lib/services/platform/platform.dart`
  /// (TASK-026's own facade tests use it), so no new test double needs
  /// hand-writing here.
  final RadioServiceController Function() radioServiceFactory;

  static SessionHost _defaultSessionFactory({
    required String localPeerId,
    required String callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
    required int initialChannel,
    required int initialCode,
  }) => RadioSessionHostAdapter(
    RadioSessionController(
      localPeerId: localPeerId,
      callsign: callsign,
      settings: settings,
      dispatch: dispatch,
      initialChannel: initialChannel,
      initialCode: initialCode,
    ),
  );

  static Future<AudioSink> _defaultAudioSinkFactory() async {
    final sink = DeviceAudioSink();
    await sink.initialize();
    return sink;
  }

  static Future<void> _defaultAudioSinkDisposer(AudioSink sink) async {
    if (sink is DeviceAudioSink) {
      await sink.dispose();
    }
  }

  static Future<DeviceIdentity> _defaultIdentityFactory() =>
      IdentityRepository(SecureIdentityStore()).loadOrCreate();

  static FacePermissionGate _defaultPermissionGateFactory() =>
      const DeviceFacePermissionGate();

  static RadioServiceController _defaultRadioServiceFactory() =>
      ChannelRadioServiceController.production();

  @override
  ConsumerState<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends ConsumerState<FaceScreen> {
  final FaceAmplitudeSource _amplitude = FaceAmplitudeSource();

  /// TASK-043: feeds the hero disc's 64-tick ring meter. `FaceAmplitudeSource`
  /// (see its own dartdoc) is the same state-driven placeholder TASK-016's
  /// review already approved for the retired grille — neither spec
  /// constrains the amplitude source, and no raw mic/RX RMS tap is exposed
  /// to the UI layer yet. `_amplitude`'s 0-0.65 scale is remapped to the
  /// ring's 0-100 scale in [_syncRingLevel]. Disclosed plainly (dossier):
  /// real per-sample TX mic RMS and real remote RX metering are both later
  /// waves — this is a documented proxy for both, not a regression from a
  /// "real" source that existed before (none did).
  final PttRingController _ringController = PttRingController(0);

  /// TASK-043: backs [RosterScreen]'s live join/depart guarantee while the
  /// screen is pushed — `setState`-triggered rebuilds of [FaceScreen] don't
  /// reach a screen that is no longer part of this widget's own subtree, so
  /// the roster needs its own listenable rather than a plain snapshot.
  final ValueNotifier<List<roster.StationInfo>> _stationsNotifier =
      ValueNotifier<List<roster.StationInfo>>(const <roster.StationInfo>[]);

  /// Relays [radioStateProvider] into [SfxProjection] as a plain broadcast
  /// `Stream<RadioState>` — the notifier itself exposes no stream (only a
  /// `Provider`/`state` getter), so this is the seam `ref.listenManual`
  /// feeds. Seeded with the current (pre-`PowerOn`) state via
  /// `fireImmediately: true` *before* `PowerOn` is dispatched in [_boot], so
  /// `SfxProjection`'s edge-detection sees the off→boot transition (a
  /// broadcast controller does not replay history to a subscriber that
  /// joins late) and plays the power-on cue.
  final StreamController<RadioState> _radioStateStream =
      StreamController<RadioState>.broadcast();

  /// Relays the active [SessionHost]'s `floorEngine.effects` into
  /// [SfxProjection]. A proxy, not a direct hookup, for the same reason
  /// `LinkedProxyFloorTransport` exists: [SfxProjection] needs a
  /// `Stream<FloorEffect>` at construction time, but the real
  /// `FloorEngine` doesn't exist until [SessionHost.start] resolves (and is
  /// torn down/rebuilt on every settings-triggered rebuild) — this proxy
  /// lets `SfxProjection` be built once, early, and just keeps getting
  /// re-pointed at whichever `FloorEngine` is currently live.
  final StreamController<FloorEffect> _floorEffectsProxy =
      StreamController<FloorEffect>.broadcast();

  /// Relays [settingsProvider] into [SfxProjection] as a plain broadcast
  /// `Stream<KeryxSettings>`, mirroring [_radioStateStream]'s pattern.
  final StreamController<KeryxSettings> _settingsStream =
      StreamController<KeryxSettings>.broadcast();

  SessionHost? _session;
  FloorEngine? _floorEngine;
  SfxEngine? _sfxEngine;
  SfxProjection? _sfxProjection;
  AudioSink? _audioSink;

  DeviceIdentity? _identity;

  /// The settings snapshot the currently-active [_session] was built from —
  /// compared against every [settingsProvider] emission to decide whether a
  /// rebuild is warranted. See [_maybeRebuildSession]'s dartdoc.
  KeryxSettings? _appliedSettings;

  /// Review round-1 finding (d): guards [_startSession] against
  /// re-entrancy. Two overlapping calls (e.g. two session-affecting
  /// settings fields changed in quick succession, both landing in
  /// [_maybeRebuildSession] before either finishes its `await
  /// session.start()`) would otherwise both resume, both write `_session`,
  /// and the loser's session/subscriptions are never disposed — a real
  /// leak (open sockets, a live `floorEngine.effects` subscription still
  /// feeding [_floorEffectsProxy]). Incremented once per call, captured
  /// before the first `await`; a call that resumes to find itself stale
  /// (superseded by a newer call) disposes what it just built instead of
  /// adopting it. See [_startSession]'s own dartdoc.
  int _sessionGeneration = 0;

  ProviderSubscription<RadioState>? _radioStateListener;
  ProviderSubscription<AsyncValue<KeryxSettings>>? _settingsListener;
  StreamSubscription<List<StationInfo>>? _stationsSub;
  StreamSubscription<FloorEffect>? _floorEffectsSub;

  /// TASK-038 foreground service (KRX-080). `null` until [_boot] constructs
  /// it (or if construction never runs because the widget was unmounted
  /// mid-boot).
  RadioServiceController? _radioService;
  StreamSubscription<RadioServiceEvent>? _radioServiceSub;

  /// Last [RadioTransportPhase] actually pushed to [_radioService] —
  /// de-dupes [_syncServicePhase] so an unrelated [RadioState] field
  /// changing (e.g. a station joining) doesn't re-issue an identical
  /// `setPhase` call on every emission.
  RadioTransportPhase? _lastServicePhase;

  /// Set when [FacePermissionGate.ensureMicrophone] resolves denied.
  /// Gates [_boot] from ever dispatching [BootCompleted] (TASK-038
  /// acceptance criterion: "radio does not enter idle") and drives
  /// [_statusOverride]'s non-modal on-face telltale (FR-045: never a
  /// modal).
  bool _micPermissionDenied = false;

  /// Non-null on a [RadioServiceFailed] event — TASK-038's "no crash,
  /// radio functional, condition surfaced on-face" requirement. Cleared
  /// only by a fresh boot (no automatic retry/recovery signal exists to
  /// clear it early; see the dossier's disclosed-decision note).
  String? _serviceFaultMessage;

  static const String _serviceFaultLabel = 'SVC FAULT';

  /// Advances [SfxEngine]'s duck envelope on a wall clock — see
  /// `SfxProjection.tick`'s own dartdoc ("Lets a polling host advance the
  /// engine's duck envelope"). 50 ms keeps the duck release well inside the
  /// engine's own timing precision without a meaningful CPU cost.
  Timer? _sfxTick;

  bool _latched = false;
  List<TunedChannel> _channelMemory = const <TunedChannel>[];
  List<roster.StationInfo> _stations = const <roster.StationInfo>[];

  @override
  void initState() {
    super.initState();
    // Riverpod forbids modifying a provider mid-build (asserts in debug/
    // profile) — `_boot`'s first dispatch would run directly from
    // `initState` otherwise. A microtask defers it to right after this
    // frame finishes building, before the first real paint.
    unawaited(Future.microtask(_boot));
  }

  Future<void> _boot() async {
    final identity = await widget.identityFactory();
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;

    // TASK-038 permissions (TS L368, KRX-092). RECORD_AUDIO is blocking —
    // the radio cannot transmit without it, so [_micPermissionDenied] gates
    // [BootCompleted] below (radio stays in `boot`, never reaches `idle`);
    // a non-modal telltale is shown via [_statusOverride] instead of any
    // dialog, per FR-045. POST_NOTIFICATIONS / NEARBY_WIFI_DEVICES are
    // non-blocking (API 33+ only; see `permission_gate.dart`'s dartdoc for
    // why no explicit SDK-version branch is needed here) — awaited
    // together only so tests can observe both deterministically, not to
    // gate anything on their result.
    final permissionGate = widget.permissionGateFactory();
    final micOutcome = await _safeEnsurePermission(
      permissionGate.ensureMicrophone,
      label: 'microphone',
    );
    if (!mounted) return;
    final micDenied = micOutcome == FacePermissionOutcome.denied;
    setState(() => _micPermissionDenied = micDenied);

    // Review round-1 finding (a): these two MUST be sequential, never
    // `Future.wait`-ed together. `permission_handler`'s Android side
    // rejects an overlapping `.request()` outright
    // (`PermissionManager.java`: "A request for permissions is already
    // running..."), so on a first launch on API 33+ — where both are
    // simultaneously not-yet-granted — running them concurrently threw a
    // `PlatformException` out of the second future, `Future.wait` rejected,
    // and `_boot` aborted before the radio ever powered on. Sequential
    // awaits are the fix; each call is also wrapped in [_safeEnsurePermission]
    // so any platform-side exception degrades to denied + a debug log
    // instead of escaping `_boot` (both are non-blocking permissions —
    // nothing here gates on the outcome, same as before).
    await _safeEnsurePermission(
      permissionGate.ensureNotifications,
      label: 'notifications',
    );
    if (!mounted) return;
    await _safeEnsurePermission(
      permissionGate.ensureNearbyWifiDevices,
      label: 'nearby Wi-Fi devices',
    );
    if (!mounted) return;

    final sink = await widget.audioSinkFactory();
    if (!mounted) {
      unawaited(widget.audioSinkDisposer(sink));
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

    if (!mounted) {
      unawaited(sfxProjection.dispose());
      sfxEngine.dispose();
      unawaited(widget.audioSinkDisposer(sink));
      return;
    }

    setState(() {
      _identity = identity;
      _audioSink = sink;
      _sfxEngine = sfxEngine;
      _sfxProjection = sfxProjection;
      _channelMemory = settings.channelMemory;
    });

    _sfxTick = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) _sfxProjection?.tick();
    });

    // `fireImmediately: true` pushes the current (still `off`) state into
    // `_radioStateStream` synchronously, right now — before `PowerOn` below
    // — establishing `SfxProjection`'s edge-detection baseline. See
    // `_radioStateStream`'s own dartdoc.
    _radioStateListener = ref.listenManual<RadioState>(radioStateProvider, (
      previous,
      next,
    ) {
      if (!_radioStateStream.isClosed) _radioStateStream.add(next);
      unawaited(_syncServicePhase(next));
    }, fireImmediately: true);
    _settingsListener = ref.listenManual<AsyncValue<KeryxSettings>>(
      settingsProvider,
      _onSettingsChanged,
    );

    _dispatch(const PowerOn());

    final initial = ref.read(radioStateProvider);

    final radioService = widget.radioServiceFactory();
    _radioServiceSub = radioService.events.listen(_onRadioServiceEvent);
    try {
      await radioService.start(
        channelLabel: _channelLabel(initial.channel, initial.privacyCode),
      );
    } catch (error, stack) {
      // TASK-038 acceptance criterion: a `start()` fault degrades
      // gracefully — the radio keeps working foregrounded, this is a
      // telltale only, never a crash. `ChannelRadioServiceController.start`
      // already logs+rethrows; this is the boundary that stops the throw
      // from reaching `_boot`'s caller.
      debugPrint('FaceScreen: radio service start failed: $error\n$stack');
      if (mounted) setState(() => _serviceFaultMessage = _serviceFaultLabel);
    }
    if (!mounted) {
      unawaited(radioService.dispose());
      return;
    }
    setState(() => _radioService = radioService);

    await _startSession(
      identity: identity,
      settings: settings,
      initialChannel: initial.channel,
      initialCode: initial.privacyCode,
    );
    if (!mounted) return;
    // Denied mic: never reach `idle` (TASK-038 acceptance criterion) — the
    // telltale from `_statusOverride` stands in for the radio being usable.
    if (!_micPermissionDenied) {
      _dispatch(const BootCompleted());
    }
  }

  /// Review round-1 finding (a), part (ii): a boundary around every
  /// [FacePermissionGate] call so a thrown `PlatformException` (or
  /// anything else the real `permission_handler` plugin can raise)
  /// degrades to [FacePermissionOutcome.denied] for that one permission
  /// and is logged, rather than escaping `_boot` and aborting it —
  /// the same shape already used for `radioService.start()` below.
  Future<FacePermissionOutcome> _safeEnsurePermission(
    Future<FacePermissionOutcome> Function() ensure, {
    required String label,
  }) async {
    try {
      return await ensure();
    } catch (error, stack) {
      debugPrint('FaceScreen: $label permission check failed: $error\n$stack');
      return FacePermissionOutcome.denied;
    }
  }

  /// `'CH 01 · 05'` — the exact `'CH XX · YY'` shape TASK-038's own
  /// description names, matching [KeryxLcdDisplay.primaryLine]'s existing
  /// zero-padded format so the persistent notification's channel label
  /// never disagrees with the glass.
  String _channelLabel(int channel, int code) =>
      'CH ${channel.toString().padLeft(2, '0')} · '
      '${code.toString().padLeft(2, '0')}';

  void _onRadioServiceEvent(RadioServiceEvent event) {
    switch (event) {
      case RadioServiceKilled():
        // TS §8.8 / FR-105: OEM/system killed the FGS without a user
        // power-off. Dispatch the honest state rather than leaving a
        // silent zombie — as far as the app is concerned the radio really
        // is off now (the native FGS, wake lock and audio focus are all
        // already gone).
        _dispatch(const PowerOff());
      case RadioServicePttAction():
        // Notification PTT is a click/toggle (`lib/services/platform`'s
        // own README: "a shade button cannot be a mechanical PTT hold"),
        // not a press-and-hold — so it toggles around whatever the
        // *floor engine's own* transmit state currently is (not
        // `radioStateProvider`'s: that only reflects `FloorEngine`'s
        // `DispatchRadio` effects once something bridges them — TASK-035's
        // `RadioStateBridge`, wired by `RadioSessionController` in
        // production, out of this task's `Owned_Paths` — and reading it
        // here would be one hop further from the truth than asking the
        // engine directly, which every other PTT entry point on this
        // screen already does). Mirrors the on-screen PTT key's own
        // press/release pair — `FloorEngine.requestTransmit`/
        // `releaseTransmit` are both idempotent no-ops in every state
        // where the toggle guess is wrong, so a stale read here is
        // harmless, not just usually-right.
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
        // itself not-running the instant this event arrives (native has
        // already torn the FGS down by the time Dart hears about it —
        // `test/services/platform/radio_service_controller_test.dart`
        // asserts `controller.isRunning == false` right after this event
        // with no `stop()` call from the host at all). Calling `.stop()`
        // here would be a same-tick no-op (`ChannelRadioServiceController
        // .stop` bails immediately once `_started` is false) — dispatching
        // the honest state is this handler's entire job, exactly like
        // `RadioServiceKilled` just above.
        _dispatch(const PowerOff());
      case RadioServiceFailed(:final message):
        // Graceful degrade: log + on-face telltale, never a crash. The
        // radio (session, floor, sound) keeps running exactly as it was.
        debugPrint('FaceScreen: radio service fault: $message');
        if (mounted) setState(() => _serviceFaultMessage = _serviceFaultLabel);
    }
  }

  /// Maps [RadioState.phase] to the native service's coarser
  /// [RadioTransportPhase] (`lib/services/platform/radio_transport_phase.dart`'s
  /// own dartdoc: `rxActive`→`rx`, `tx`/`txRequest`→`tx`, everything else
  /// powered-on→`idle`) and pushes it through only on an actual change, so
  /// unrelated [RadioState] emissions (a station joining, a signal-quality
  /// tick) don't re-issue an identical `setPhase` call. A no-op before the
  /// service has started (nothing to push to yet) or after it has stopped.
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
      debugPrint('FaceScreen: radio service setPhase failed: $error\n$stack');
    }
  }

  void _dispatch(RadioEvent event) =>
      ref.read(radioStateProvider.notifier).dispatch(event);

  /// (Re)builds the active [SessionHost]. Called once from [_boot] and
  /// again from [_maybeRebuildSession] on a session-affecting settings
  /// change or from [_retuneSession] on a channel change. Tears down
  /// whatever session/subscriptions are currently active first — safe to
  /// call with `_session == null` (the first-boot case).
  ///
  /// **Re-entrancy (review round-1 finding (d)).** `session.start()` is a
  /// real suspension point (LOCAL binds UDP sockets and runs discovery), so
  /// two overlapping calls are possible whenever two session-affecting
  /// settings fields change close together. [_sessionGeneration] is
  /// captured on entry and re-checked after the `await`: a call that
  /// resumes to find a newer call already in flight (or already landed)
  /// disposes the session it just started instead of adopting it, so
  /// exactly one — the most recent — session ever ends up assigned to
  /// [_session].
  Future<void> _startSession({
    required DeviceIdentity identity,
    required KeryxSettings settings,
    required int initialChannel,
    required int initialCode,
  }) async {
    final myGeneration = ++_sessionGeneration;
    final previousSession = _session;
    await _stationsSub?.cancel();
    _stationsSub = null;
    await _floorEffectsSub?.cancel();
    _floorEffectsSub = null;
    if (previousSession != null) {
      // Review round-1 finding (e), non-blocking: a throw here was
      // previously invisible (bare `unawaited`). `debugPrint` is a cheap
      // telltale — no user-visible error surface exists for a
      // teardown-path failure yet, so this at least reaches the device log
      // instead of vanishing into the zone.
      unawaited(
        previousSession.dispose().catchError(
          (Object error, StackTrace stack) => debugPrint(
            'FaceScreen: previous session dispose failed: $error\n$stack',
          ),
        ),
      );
    }
    _stationsNotifier.value = const <roster.StationInfo>[];
    if (mounted) {
      setState(() {
        _session = null;
        _floorEngine = null;
        _stations = const <roster.StationInfo>[];
      });
    }

    final session = widget.sessionFactory(
      localPeerId: identity.peerId,
      callsign: identity.callsign.value,
      settings: settings,
      dispatch: _dispatch,
      initialChannel: initialChannel,
      initialCode: initialCode,
    );
    await session.start();
    if (!mounted || myGeneration != _sessionGeneration) {
      // Torn down, or superseded by a newer `_startSession` call that
      // arrived while this one was suspended in `session.start()` — either
      // way this session must not become `_session`. Dispose it rather
      // than leak its transport/sockets.
      unawaited(session.dispose());
      return;
    }

    _appliedSettings = settings;
    _floorEffectsSub = session.floorEngine.effects.listen((effect) {
      if (!_floorEffectsProxy.isClosed) _floorEffectsProxy.add(effect);
    });
    _stationsSub = session.stations.listen((stations) {
      if (!mounted) return;
      final mapped = stations.map(_toRosterStation).toList(growable: false);
      _stationsNotifier.value = mapped;
      setState(() => _stations = mapped);
    });

    setState(() {
      _session = session;
      _floorEngine = session.floorEngine;
    });
  }

  void _onSettingsChanged(
    AsyncValue<KeryxSettings>? previous,
    AsyncValue<KeryxSettings> next,
  ) {
    final settings = next.valueOrNull;
    // Still loading, or a load error — keep whatever session is already
    // running rather than tearing it down over a transient read failure.
    if (settings == null) return;
    if (!_settingsStream.isClosed) _settingsStream.add(settings);
    unawaited(_maybeRebuildSession(settings));
  }

  /// **Disclosed decision — rebuild the session, don't live-patch it.**
  /// `RadioSessionController`'s own dartdoc (TASK-035) is explicit that
  /// settings are a construction-time snapshot: "a meaningfully different
  /// settings value … needs a new `RadioSessionController` from the host."
  /// So "a settings change made [in the back panel] is observed by the face
  /// without restart" is satisfied at this boundary by tearing down and
  /// reconstructing the session on the session-affecting subset of fields
  /// ([_sessionAffectingFieldsChanged]) — matching that precedent exactly
  /// rather than asking the session layer to react live to arbitrary
  /// setting flips.
  Future<void> _maybeRebuildSession(KeryxSettings settings) async {
    final identity = _identity;
    final applied = _appliedSettings;
    if (identity == null || applied == null) {
      return; // no session yet to rebuild (still booting)
    }
    if (!_sessionAffectingFieldsChanged(applied, settings)) {
      _appliedSettings = settings;
      return;
    }
    final state = ref.read(radioStateProvider);
    await _startSession(
      identity: identity,
      settings: settings,
      initialChannel: state.channel,
      initialCode: state.privacyCode,
    );
  }

  /// The subset of [KeryxSettings] that actually changes which transport
  /// chain (or which channel-scoped resources within it) `RadioSessionController`
  /// builds — see its `_resolveEffectiveMode`/`_startLocal`/`_startLinked`.
  /// Everything else (squelch, roger beep, DSP intensity, …) is consumed
  /// downstream of the session (by [SfxProjection]/[SfxEngine] directly via
  /// [_settingsStream]) and does not warrant tearing the session down.
  bool _sessionAffectingFieldsChanged(KeryxSettings a, KeryxSettings b) =>
      a.mode != b.mode ||
      a.forceLocalOnly != b.forceLocalOnly ||
      a.relayUrl != b.relayUrl ||
      a.tokenServiceUrl != b.tokenServiceUrl ||
      a.totSeconds != b.totSeconds ||
      a.busyLockout != b.busyLockout ||
      a.region != b.region;

  roster.StationInfo _toRosterStation(StationInfo station) {
    final peerId = station.peerId.isEmpty ? 'unknown-peer' : station.peerId;
    final callsign = station.callsign.isEmpty ? peerId : station.callsign;
    return roster.StationInfo(
      peerId: peerId,
      callsign: callsign,
      signalQuality: station.signalQuality,
    );
  }

  @override
  void dispose() {
    _sfxTick?.cancel();
    unawaited(_stationsSub?.cancel());
    unawaited(_floorEffectsSub?.cancel());
    _radioStateListener?.close();
    _settingsListener?.close();
    unawaited(_sfxProjection?.dispose());
    _sfxEngine?.dispose();
    final sink = _audioSink;
    if (sink != null) unawaited(widget.audioSinkDisposer(sink));
    unawaited(_session?.dispose());
    unawaited(_radioServiceSub?.cancel());
    unawaited(_radioService?.dispose());
    unawaited(_radioStateStream.close());
    unawaited(_floorEffectsProxy.close());
    unawaited(_settingsStream.close());
    _amplitude.dispose();
    _ringController.dispose();
    _stationsNotifier.dispose();
    super.dispose();
  }

  int _clampChannel(int channel) =>
      channel.clamp(RadioState.minimumChannel, RadioState.maximumChannel);

  int _clampCode(int code) =>
      code.clamp(RadioState.minimumPrivacyCode, RadioState.maximumPrivacyCode);

  void _tuneTo(int channel, int code) {
    final clampedChannel = _clampChannel(channel);
    final clampedCode = _clampCode(code);
    _dispatch(TuneTo(channel: clampedChannel, privacyCode: clampedCode));
    unawaited(_retuneSession(clampedChannel, clampedCode));
    final entry = TunedChannel(channel: clampedChannel, privacyCode: clampedCode);
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .rememberChannel(entry)
          .then((updated) {
            if (mounted) setState(() => _channelMemory = updated.channelMemory);
          }),
    );
  }

  /// Channel-scoped retune: `RadioSessionController.retune`'s own contract
  /// is a full teardown/rebuild of the channel-scoped parts (LOCAL's
  /// discovery/signaling bind, LINKED's room id are both derived from
  /// channel+code), so a tune has to rebuild the transport, not just the
  /// reducer's numeral. A no-op before the session has finished its first
  /// [SessionHost.start] — nothing to retune yet, and the very next `start()`
  /// already carries whatever channel is current by then.
  Future<void> _retuneSession(int channel, int code) async {
    final session = _session;
    if (session != null) {
      try {
        await session.retune(channel: channel, code: code);
      } catch (error, stack) {
        // Review round-1 finding (e), non-blocking: see `_startSession`'s
        // dispose-failure telltale for the same rationale.
        debugPrint('FaceScreen: retune failed: $error\n$stack');
      }
    }

    // TASK-038: keep the persistent notification's channel label in sync
    // on every retune, independent of session state — a tune can arrive
    // before the very first `session.start()` resolves (session == null
    // above), and the notification should still show the right channel
    // the moment it exists.
    final service = _radioService;
    if (service != null && service.isRunning) {
      try {
        await service.updateNotification(
          channelLabel: _channelLabel(channel, code),
        );
      } catch (error, stack) {
        debugPrint(
          'FaceScreen: radio service updateNotification failed: '
          '$error\n$stack',
        );
      }
    }
  }

  void _tuneChannelDelta(RadioState state, int delta) {
    // FR-003/004: knob and steppers both write to the same tuning state
    // machine via absolute TuneTo. Boundary behaviour is CLAMP, not wrap,
    // per ORCH's 2026-08-19 ruling on follow-up (k) — `RadioReducer`
    // exposes no `tuneDelta` event, so the clamp is resolved here, once,
    // for every delta-emitting control (same pattern `KeryxTuningKnob`
    // already established internally for its own physics layer).
    final next = _clampChannel(state.channel + delta);
    if (next == state.channel) return;
    _tuneTo(next, state.privacyCode);
  }

  /// TASK-043: extended for the hero disc's two new visual states —
  /// [PttState.emergency] (active emergency, checked first: it overrides
  /// every other visual per the approved canvas's Emergency artboard) and
  /// [PttState.receiving] (another station holds the floor). Neither is a
  /// new state *source* — both read off the same `RadioState` fields the
  /// old PTT key already used (`isEmergency`, `phase == rxActive`).
  PttState _pttStateFor(RadioState state) {
    if (state.isEmergency) return PttState.emergency;
    if (state.isTransmitDenied) return PttState.denied;
    if (state.phase == RadioPhase.txRequest) return PttState.requesting;
    if (state.phase == RadioPhase.tx) {
      return _latched ? PttState.latched : PttState.granted;
    }
    if (state.phase == RadioPhase.rxActive) return PttState.receiving;
    return PttState.idle;
  }

  void _onPttPressStart() => _floorEngine?.requestTransmit();

  void _onPttPressEnd() {
    if (_latched) return; // stays keyed until the latch is explicitly released
    _floorEngine?.releaseTransmit();
  }

  void _onLatchToggled(bool engaged) {
    setState(() => _latched = engaged);
    if (!engaged) _floorEngine?.releaseTransmit();
  }

  void _onEmergencyToggled() {
    final engine = _floorEngine;
    if (engine == null) return;
    if (engine.isEmergencyPinned &&
        engine.emergencyPeer == engine.localPeerId) {
      engine.clearEmergency();
    } else {
      engine.requestTransmit(emergency: true);
    }
  }

  void _onDirectTuneRequested(BuildContext context, RadioState state) {
    unawaited(
      showKeryxKeypadSheet(
        context,
        initialChannel: state.channel,
        initialPrivacyCode: state.privacyCode,
        onConfirm: _tuneTo,
      ),
    );
  }

  void _onRecallRequested(BuildContext context) {
    unawaited(
      showChannelRecallPanel(
        context,
        entries: _channelMemory,
        onSelect: (entry) => _tuneTo(entry.channel, entry.privacyCode),
      ),
    );
  }

  /// TASK-043: FR-067's successor — opens the full-screen [RosterScreen]
  /// (replacing the old flip-panel STN treatment). Pushed from both the
  /// header's STN tap and the rail's STN-labelled key (`_railRegion`'s
  /// `onSayAgain`).
  void _openRoster(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (rosterContext) => RosterScreen(
            stations: _stationsNotifier,
            onScan: () => _onScanQr(rosterContext),
            onExport: () => _onExportQr(rosterContext, ref.read(radioStateProvider)),
          ),
        ),
      ),
    );
  }

  /// FR-043/FR-044 scan entry point — pushed from [RosterScreen]'s app bar.
  /// A no-op before the first session exists (nothing to `joinEvent` into
  /// yet); [EventQrScanScreen] itself owns the camera lifecycle. The old
  /// glass-flip pause/resume dance is gone with the flip panel it protected
  /// — the roster is now its own full-screen route, so there is no
  /// background auto-flip timer to race against.
  void _onScanQr(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (scanContext) => Scaffold(
            appBar: AppBar(title: const Text('Scan event QR')),
            body: EventQrScanScreen(
              onTuned: (payload) =>
                  unawaited(_joinEvent(scanContext, payload)),
            ),
          ),
        ),
      ),
    );
  }

  /// Review round-1 finding (e), non-blocking: [SessionHost.joinEvent]
  /// "requires an already-active LINKED chain" (see its own dartdoc) — a
  /// scan while LOCAL was previously a silent no-op per FR-044 ("scanning
  /// tunes the radio instantly"). A snackbar is a cheap, visible telltale;
  /// it does not replace a real LOCAL->LINKED prompt flow, which is out of
  /// this task's scope.
  Future<void> _joinEvent(BuildContext context, EventLinkPayload payload) async {
    final session = _session;
    if (session == null) return;
    try {
      await session.joinEvent(payload);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not join event: $error')),
      );
    }
  }

  /// FR-043/FR-044 export entry point — see [_onScanQr]'s placement note.
  /// Only the numbered-channel case is wired here: a keyed-channel export
  /// needs [buildKeyedEventLink]'s passphrase input, which has no home in
  /// this face yet (out of this task's scope; the export screen itself
  /// already supports it via its `payloadBuilder` seam for whoever wires
  /// that up later).
  void _onExportQr(BuildContext context, RadioState state) {
    final region = _appliedSettings?.region ?? KeryxSettings.defaultRegion;
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Export event QR')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: EventQrExportScreen(
                payloadBuilder: (expiresAt) => NumberedEventLink(
                  region: region,
                  channel: state.channel,
                  code: state.privacyCode,
                  expiresAt: expiresAt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// TASK-043: TX uses the same state-driven [_amplitude] proxy the retired
  /// grille used (0-0.65 "active" scale, see [_amplitude]'s dartdoc);
  /// documented RX proxy is identical — neither the disc nor the spec
  /// distinguishes a TX-only vs RX-only source yet, so both drive the same
  /// ring off the same [RadioPhase] signal until a real audio-engine RMS
  /// tap is wired (later wave, matching TASK-016/041's precedent).
  void _syncRingLevel(RadioState state) {
    _amplitude.update(state);
    // FaceAmplitudeSource eases 0 -> 0.65 on its own 90ms timer; sample its
    // *target* here (cheap, synchronous) rather than subscribing to its
    // stream a second time — the disc's ring only needs "is something
    // active right now", not the same smoothing curve as the retired
    // grille's tremble animation.
    final active =
        state.phase == RadioPhase.tx ||
        state.phase == RadioPhase.rxActive ||
        state.isMonitorOpen;
    _ringController.setLevel(active ? 65 : 8);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(radioStateProvider);
    _syncRingLevel(state);
    return FaceView(
      state: state,
      stations: _stations,
      ringLevel: _ringController,
      pttState: _pttStateFor(state),
      batteryLevel: 1.0,
      onStep: (delta) => _tuneChannelDelta(state, delta),
      onDirectTuneRequested: () => _onDirectTuneRequested(context, state),
      onRecallRequested: () => _onRecallRequested(context),
      onPttPressStart: _onPttPressStart,
      onPttPressEnd: _onPttPressEnd,
      onLatchToggled: _onLatchToggled,
      onMonHoldStart: () => _dispatch(const MonitorChanged(true)),
      onMonHoldEnd: () => _dispatch(const MonitorChanged(false)),
      onScan: () => _dispatch(ScanChanged(!state.isScanning)),
      onOpenRoster: () => _openRoster(context),
      onSettings: () => Navigator.of(context).pushNamed(backPanelRouteName),
      onEmergencyToggled: _onEmergencyToggled,
      onScanQr: () => _onScanQr(context),
      onExportQr: () => _onExportQr(context, state),
      statusOverride: _statusOverride(),
    );
  }

  /// TASK-038 non-modal telltale (FR-045). Mic denial takes priority over
  /// a service fault (a mic-less radio can't be usable at all regardless
  /// of the FGS; the two are exceedingly unlikely to both be true, but the
  /// priority order still has to be someone's disclosed decision).
  String? _statusOverride() {
    if (_micPermissionDenied) return 'MIC REQUIRED';
    if (_serviceFaultMessage != null) return _serviceFaultMessage;
    return null;
  }
}
