import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_bridge.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/ptt/ptt.dart';
import 'package:keryx/features/tuning/tuning.dart';

import 'amplitude_source.dart';
import 'face_view.dart';
import 'glass_flip_controller.dart';
import 'local_floor_transport.dart';
import 'roster.dart';

/// Boots identity + the floor engine, then renders [FaceView] as a live
/// projection of [radioStateProvider] — the app's actual home screen.
///
/// This is the sole owner of the [FloorEngine] instance: it constructs one
/// [LocalFloorTransport]-backed engine per app session, bridges its effects
/// into the reducer via [RadioStateBridge], and tears both down on dispose.
/// No other widget in `lib/features/face/**` touches `FloorEngine` or
/// `RadioStateController` directly — the reducer is the single state source
/// TS §8.2 requires; [FaceView] only ever receives values, never mutates
/// them.
class FaceScreen extends ConsumerStatefulWidget {
  const FaceScreen({super.key});

  @override
  ConsumerState<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends ConsumerState<FaceScreen> {
  final GlassFlipController _flipController = GlassFlipController();
  final FaceAmplitudeSource _amplitude = FaceAmplitudeSource();
  final SettingsRepository _settings = SettingsRepository(SecureSettingsStore());

  FloorEngine? _floorEngine;
  LocalFloorTransport? _transport;
  RadioStateBridge? _bridge;
  bool _latched = false;
  List<TunedChannel> _channelMemory = const <TunedChannel>[];

  /// No live roster feed exists until TASK-020 (`lib/services/signaling/**`)
  /// ships — see `roster.dart`'s dartdoc. Empty is the honest default.
  final List<StationInfo> _stations = const <StationInfo>[];

  @override
  void initState() {
    super.initState();
    // Riverpod forbids modifying a provider mid-build (asserts in debug/
    // profile) — `_boot`'s first line dispatches synchronously, so it can't
    // run directly from `initState`. A microtask defers it to right after
    // this frame finishes building, before the first real paint.
    unawaited(Future.microtask(_boot));
  }

  Future<void> _boot() async {
    _dispatch(const PowerOn());
    final identity = await IdentityRepository(
      SecureIdentityStore(),
    ).loadOrCreate();
    final settings = await _settings.load();
    if (!mounted) return;
    final transport = LocalFloorTransport();
    final engine = FloorEngine(
      localPeerId: identity.peerId,
      transport: transport,
      clock: const WallClock(),
      tot: Duration(seconds: settings.totSeconds),
      busyLockout: settings.busyLockout,
    );
    engine.updateRoster(<String>{identity.peerId});
    final bridge = RadioStateBridge(engine: engine, dispatch: _dispatch);
    setState(() {
      _transport = transport;
      _floorEngine = engine;
      _bridge = bridge;
      _channelMemory = settings.channelMemory;
    });
    _dispatch(const BootCompleted());
  }

  void _dispatch(RadioEvent event) =>
      ref.read(radioStateProvider.notifier).dispatch(event);

  @override
  void dispose() {
    unawaited(_bridge?.dispose());
    _floorEngine?.dispose();
    _transport?.dispose();
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
    final entry = TunedChannel(channel: clampedChannel, privacyCode: clampedCode);
    unawaited(
      _settings.rememberChannel(entry).then((updated) {
        if (mounted) setState(() => _channelMemory = updated.channelMemory);
      }),
    );
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
      onSayAgain: () {}, // FR-046 replay playback is core/audio's territory; no hook exists yet
      onSettings: () {}, // TASK-018 (settings panel) is still TBD; no screen to open yet
      onEmergencyToggled: _onEmergencyToggled,
    );
  }
}
