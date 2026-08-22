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
import 'package:keryx/services/session/session.dart'
    show RadioSessionController, StationInfo;
import 'package:keryx/services/sound/sound.dart';

import 'amplitude_source.dart';
import 'face_view.dart';
import 'glass_flip_controller.dart';
import 'roster.dart' as roster;
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

  @override
  ConsumerState<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends ConsumerState<FaceScreen> {
  final GlassFlipController _flipController = GlassFlipController();
  final FaceAmplitudeSource _amplitude = FaceAmplitudeSource();

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

  ProviderSubscription<RadioState>? _radioStateListener;
  ProviderSubscription<AsyncValue<KeryxSettings>>? _settingsListener;
  StreamSubscription<List<StationInfo>>? _stationsSub;
  StreamSubscription<FloorEffect>? _floorEffectsSub;

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
    }, fireImmediately: true);
    _settingsListener = ref.listenManual<AsyncValue<KeryxSettings>>(
      settingsProvider,
      _onSettingsChanged,
    );

    _dispatch(const PowerOn());

    final initial = ref.read(radioStateProvider);
    await _startSession(
      identity: identity,
      settings: settings,
      initialChannel: initial.channel,
      initialCode: initial.privacyCode,
    );
    if (!mounted) return;
    _dispatch(const BootCompleted());
  }

  void _dispatch(RadioEvent event) =>
      ref.read(radioStateProvider.notifier).dispatch(event);

  /// (Re)builds the active [SessionHost]. Called once from [_boot] and
  /// again from [_maybeRebuildSession] on a session-affecting settings
  /// change or from [_retuneSession] on a channel change. Tears down
  /// whatever session/subscriptions are currently active first — safe to
  /// call with `_session == null` (the first-boot case).
  Future<void> _startSession({
    required DeviceIdentity identity,
    required KeryxSettings settings,
    required int initialChannel,
    required int initialCode,
  }) async {
    final previousSession = _session;
    await _stationsSub?.cancel();
    _stationsSub = null;
    await _floorEffectsSub?.cancel();
    _floorEffectsSub = null;
    if (previousSession != null) {
      unawaited(previousSession.dispose());
    }
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
    if (!mounted) {
      unawaited(session.dispose());
      return;
    }

    _appliedSettings = settings;
    _floorEffectsSub = session.floorEngine.effects.listen((effect) {
      if (!_floorEffectsProxy.isClosed) _floorEffectsProxy.add(effect);
    });
    _stationsSub = session.stations.listen((stations) {
      if (!mounted) return;
      setState(
        () => _stations = stations
            .map(_toRosterStation)
            .toList(growable: false),
      );
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
    unawaited(_radioStateStream.close());
    unawaited(_floorEffectsProxy.close());
    unawaited(_settingsStream.close());
    _flipController.dispose();
    _amplitude.dispose();
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
    if (session == null) return;
    await session.retune(channel: channel, code: code);
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

  PttState _pttStateFor(RadioState state) {
    if (state.isTransmitDenied) return PttState.denied;
    if (state.phase == RadioPhase.txRequest) return PttState.requesting;
    if (state.phase == RadioPhase.tx) {
      return _latched ? PttState.latched : PttState.granted;
    }
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

  /// FR-043/FR-044 scan entry point — pushed from [StationListPanel]'s
  /// header (see `FaceView`'s own dartdoc for that placement decision). A
  /// no-op before the first session exists (nothing to `joinEvent` into
  /// yet); [EventQrScanScreen] itself owns the camera lifecycle.
  void _onScanQr(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Scan event QR')),
            body: EventQrScanScreen(
              onTuned: (payload) => unawaited(_session?.joinEvent(payload)),
            ),
          ),
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(radioStateProvider);
    _amplitude.update(state);
    return FaceView(
      state: state,
      stations: _stations,
      amplitude: _amplitude.stream,
      flipController: _flipController,
      pttState: _pttStateFor(state),
      batteryLevel: 1.0,
      onDetent: (delta) => _tuneChannelDelta(state, delta),
      onStep: (delta) => _tuneChannelDelta(state, delta),
      onDirectTuneRequested: () => _onDirectTuneRequested(context, state),
      onRecallRequested: () => _onRecallRequested(context),
      onPttPressStart: _onPttPressStart,
      onPttPressEnd: _onPttPressEnd,
      onLatchToggled: _onLatchToggled,
      onMonHoldStart: () => _dispatch(const MonitorChanged(true)),
      onMonHoldEnd: () => _dispatch(const MonitorChanged(false)),
      onScan: () => _dispatch(ScanChanged(!state.isScanning)),
      // FR-065 replay playback is a later wave (Pro feature); handler stays
      // empty until that lands. (Not FR-046 — that FR is the force-local-only
      // privacy toggle, unrelated to this key.)
      onSayAgain: () {},
      onSettings: () => Navigator.of(context).pushNamed(backPanelRouteName),
      onEmergencyToggled: _onEmergencyToggled,
      onScanQr: () => _onScanQr(context),
      onExportQr: () => _onExportQr(context, state),
    );
  }
}
