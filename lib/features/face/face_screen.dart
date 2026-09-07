import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/event_qr/qr_export_screen.dart';
import 'package:keryx/features/event_qr/qr_scan_screen.dart';
import 'package:keryx/features/ptt/ptt.dart';
import 'package:keryx/features/settings_panel/back_panel_screen.dart';
import 'package:keryx/features/tuning/tuning.dart';
import 'package:keryx/services/platform/platform.dart' show ChannelRadioServiceController, RadioServiceController;
import 'package:keryx/services/session/session.dart'
    show RadioSessionController, StationInfo;

import 'amplitude_source.dart';
import 'face_view.dart';
import 'permission_gate.dart';
import 'roster.dart' as roster;
import 'roster_screen.dart';
import 'session_host.dart';

/// TASK-045: `FaceScreen` no longer owns the radio's lifecycle — it
/// constructs a [RadioHost] (see `lib/core/radio_host/**`) at the same
/// point in the widget tree it used to construct the session/audio/service
/// stack directly, and from then on only *consumes* that host: it renders
/// [radioStateProvider] (unchanged — the host never duplicates that state),
/// subscribes to [RadioHost.changes] for the side state the host owns
/// (permission/service condition, stations, channel memory, the live
/// [FloorEngine] reference), and forwards every user gesture to a host
/// method or, for read-only TX-ownership truth the host's narrow contract
/// doesn't expose a dedicated method for (emergency pin/clear), to
/// `host.current.floorEngine` directly — Technical §3: "The actual floor
/// engine remains the source of truth for TX ownership".
///
/// The host itself is still created here, not above the navigator —
/// hoisting it there is TASK-048's job (Technical §9: "A separate
/// integration task owns shared route registration, app.dart, shared
/// providers and final wiring"). `lib/app.dart`/`lib/main.dart` are
/// deliberately untouched by this task.
///
/// **Testability — constructor-injected factories, unchanged.** Every
/// factory field below has exactly the same name, type and default as
/// before TASK-045 — `sessionFactory`/`audioSinkFactory`/
/// `audioSinkDisposer`/`identityFactory`/`permissionGateFactory`/
/// `radioServiceFactory` are forwarded straight into [KeryxRadioHost]'s
/// constructor. Every existing test double written against this widget's
/// public API keeps working unmodified.
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

  final Future<void> Function(AudioSink sink) audioSinkDisposer;

  final Future<DeviceIdentity> Function() identityFactory;

  final FacePermissionGate Function() permissionGateFactory;

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

  /// TASK-043: feeds the hero disc's 64-tick ring meter. See `FaceAmplitudeSource`'s
  /// own dartdoc — a documented proxy, not a regression from a "real" source
  /// that existed before (none did); unaffected by TASK-045.
  final PttRingController _ringController = PttRingController(0);

  /// TASK-043: backs [RosterScreen]'s live join/depart guarantee while the
  /// screen is pushed. Now fed from [RadioHost.changes] instead of a direct
  /// session subscription — the subscription itself moved into the host
  /// (Technical §1.1: "station notifier" is explicitly one of the things
  /// `FaceScreen` must no longer own).
  final ValueNotifier<List<roster.StationInfo>> _stationsNotifier =
      ValueNotifier<List<roster.StationInfo>>(const <roster.StationInfo>[]);

  late final RadioHost _host;
  StreamSubscription<RadioHostSnapshot>? _hostSub;

  bool _latched = false;
  List<TunedChannel> _channelMemory = const <TunedChannel>[];
  List<roster.StationInfo> _stations = const <roster.StationInfo>[];
  bool _micPermissionDenied = false;
  String? _serviceFaultMessage;

  @override
  void initState() {
    super.initState();
    _host = KeryxRadioHost(
      sessionFactory: widget.sessionFactory,
      audioSinkFactory: widget.audioSinkFactory,
      audioSinkDisposer: widget.audioSinkDisposer,
      identityFactory: widget.identityFactory,
      permissionGateFactory: widget.permissionGateFactory,
      radioServiceFactory: widget.radioServiceFactory,
      loadSettings: () => ref.read(settingsProvider.future),
      dispatch: (event) => ref.read(radioStateProvider.notifier).dispatch(event),
      readRadioState: () => ref.read(radioStateProvider),
      rememberChannel: (channel) =>
          ref.read(settingsProvider.notifier).rememberChannel(channel),
      listenRadioState: (onChange, {bool fireImmediately = false}) {
        final subscription = ref.listenManual<RadioState>(
          radioStateProvider,
          (previous, next) => onChange(previous, next),
          fireImmediately: fireImmediately,
        );
        return subscription.close;
      },
      listenSettings: (onChange) {
        final subscription = ref.listenManual<AsyncValue<KeryxSettings>>(
          settingsProvider,
          (previous, next) {
            final settings = next.valueOrNull;
            // Still loading, or a load error — keep whatever session is
            // already running rather than tearing it down over a
            // transient read failure.
            if (settings != null) onChange(settings);
          },
        );
        return subscription.close;
      },
    );
    _hostSub = _host.changes.listen(_onHostSnapshot);
    // Riverpod forbids modifying a provider mid-build (asserts in debug/
    // profile) — `_host.start()`'s first dispatch would run directly from
    // `initState` otherwise. A microtask defers it to right after this
    // frame finishes building, before the first real paint.
    unawaited(Future.microtask(_host.start));
  }

  void _onHostSnapshot(RadioHostSnapshot snapshot) {
    if (!mounted) return;
    setState(() {
      _micPermissionDenied = snapshot.micPermissionDenied;
      _serviceFaultMessage = snapshot.serviceFaultMessage;
      _channelMemory = snapshot.channelMemory;
      _stations = snapshot.stations.map(_toRosterStation).toList(growable: false);
    });
    _stationsNotifier.value = _stations;
  }

  void _dispatch(RadioEvent event) =>
      ref.read(radioStateProvider.notifier).dispatch(event);

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
    unawaited(_hostSub?.cancel());
    unawaited(_host.dispose());
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
    unawaited(_host.tune(clampedChannel, clampedCode));
  }

  void _tuneChannelDelta(RadioState state, int delta) {
    // FR-003/004: knob and steppers both write to the same tuning state
    // machine via absolute TuneTo. Boundary behaviour is CLAMP, not wrap.
    final next = _clampChannel(state.channel + delta);
    if (next == state.channel) return;
    _tuneTo(next, state.privacyCode);
  }

  /// TASK-043: extended for the hero disc's two new visual states —
  /// [PttState.emergency] and [PttState.receiving].
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

  void _onPttPressStart() => _host.pressPtt();

  void _onPttPressEnd() {
    if (_latched) return; // stays keyed until the latch is explicitly released
    _host.releasePtt();
  }

  void _onLatchToggled(bool engaged) {
    setState(() => _latched = engaged);
    if (!engaged) _host.releaseLatch();
  }

  /// Emergency pin/clear reads/writes the authoritative [FloorEngine]
  /// directly via [RadioHostSnapshot.floorEngine] — [RadioHost]'s narrow
  /// contract (Technical §3) does not name a dedicated emergency
  /// operation, and the engine is explicitly documented as "the source of
  /// truth for TX ownership" a caller may consult directly for anything
  /// the contract doesn't cover.
  void _onEmergencyToggled() {
    final engine = _host.current.floorEngine;
    if (engine == null) return;
    if (engine.isEmergencyPinned && engine.emergencyPeer == engine.localPeerId) {
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

  /// TASK-043: opens the full-screen [RosterScreen].
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

  /// FR-043/FR-044 scan entry point.
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

  Future<void> _joinEvent(BuildContext context, EventLinkPayload payload) async {
    final result = await _host.joinEvent(payload);
    if (result.isSuccess) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not join event: ${result.message ?? result.outcome}')),
    );
  }

  /// FR-043/FR-044 export entry point. Reads the region straight off the
  /// live settings provider rather than a widget-cached field — TASK-045
  /// no longer keeps a local `_appliedSettings` mirror (that snapshot now
  /// lives only inside the host, scoped to session-affecting fields it
  /// actually needs; `region` is read fresh here instead of duplicated).
  void _onExportQr(BuildContext context, RadioState state) {
    final region =
        ref.read(settingsProvider).valueOrNull?.region ?? KeryxSettings.defaultRegion;
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

  /// TASK-043: TX/RX ring proxy — unaffected by TASK-045 (still a
  /// documented `RadioState`-phase-driven proxy, not a real audio tap).
  void _syncRingLevel(RadioState state) {
    _amplitude.update(state);
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
  /// a service fault.
  String? _statusOverride() {
    if (_micPermissionDenied) return 'MIC REQUIRED';
    if (_serviceFaultMessage != null) return _serviceFaultMessage;
    return null;
  }
}
