import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/floor/floor.dart'
    show EmgCleared, EmgPinned, FloorEffect, FloorEngine;
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'radio_controls_copy.dart';

/// Keys for widget tests (Design §2.5).
abstract final class RadioControlsKeys {
  static const Key title = Key('radio-controls.title');

  static const Key monitorRow = Key('radio-controls.monitor.row');
  static const Key monitorHoldTarget = Key(
    'radio-controls.monitor.hold-target',
  );
  static const Key monitorIndicator = Key('radio-controls.monitor.indicator');
  static const Key monitorUnavailable = Key(
    'radio-controls.monitor.unavailable',
  );

  static const Key scanRow = Key('radio-controls.scan.row');
  static const Key scanSwitch = Key('radio-controls.scan.switch');
  static const Key scanIndicator = Key('radio-controls.scan.indicator');
  static const Key scanUnavailable = Key('radio-controls.scan.unavailable');

  static const Key emergencyRow = Key('radio-controls.emergency.row');
  static const Key emergencyHoldTarget = Key(
    'radio-controls.emergency.hold-target',
  );
  static const Key emergencyBanner = Key('radio-controls.emergency.banner');
  static const Key emergencyClear = Key('radio-controls.emergency.clear');
  static const Key emergencyArming = Key('radio-controls.emergency.arming');
  static const Key emergencyUnavailable = Key(
    'radio-controls.emergency.unavailable',
  );
  static const Key emergencyClearedByOther = Key(
    'radio-controls.emergency.cleared-by-other',
  );
}

/// Design §2.5 — the successor home for the legacy four-key rail's actual
/// functions (Monitor, Scan, Emergency), built fresh rather than reusing
/// `lib/features/ptt/key_row.dart`/`emg_key.dart` (ADR-001 §7 item 2).
///
/// Latch is PTT-hold-scoped (`lib/features/talk/talk_screen.dart`'s
/// `TalkLatchState`) and has no meaning as a standalone control here; VOX
/// and Replay have no production trigger path anywhere in the repo today
/// (`RadioStateBridge.updateVox`/`updateReplay` are telemetry-*ingress*
/// only, never fired from a UI action) — so per the honesty rule
/// ("unimplemented entries are absent, not faked", UX-FR-041), only
/// Monitor, Scan and Emergency are rendered. See dossiers/TASK-054.md for
/// the full reasoning trail.
///
/// [host] is injected by the caller (`lib/app_shell/**`), mirroring
/// `TalkScreen`'s documented rule that `lib/features/**` does not depend on
/// `lib/app_shell/**`.
///
/// Monitor/Scan have no `RadioHost`/`RadioViewIntents` entry points (a
/// confirmed architecture gap, not an oversight of this task) — they are
/// pure local `RadioState` toggles with no session/transport side effect
/// (`RadioReducer`'s `MonitorChanged`/`ScanChanged` cases are plain
/// `copyWith` calls), so this screen dispatches them the same way the
/// legacy `face_screen.dart` already does today:
/// `ref.read(radioStateProvider.notifier).dispatch(...)`. Emergency is the
/// one control with a real engine-owned side effect, so it goes straight
/// through `RadioHostSnapshot.floorEngine` — the sanctioned direct-access
/// seam `RadioHostSnapshot`'s own dartdoc names for exactly this
/// ("operations `RadioHost` itself does not narrowly expose, e.g.
/// emergency pin/clear") — using the *exact* existing hold-arm duration
/// and grant/clear logic `face_screen._onEmergencyToggled` already uses,
/// per Design §2.5/UX-D06's "preserve the existing... unless a separate
/// ADR changes them".
///
/// **FR-025's emergency-preemption double-grant stays PARKED** (ADR-001
/// §5) — this screen never touches floor arbitration; anything observed
/// wrong at the engine level is a finding, not a fix, here.
class RadioControlsScreen extends ConsumerStatefulWidget {
  const RadioControlsScreen({super.key, required this.host});

  final RadioHost host;

  @override
  ConsumerState<RadioControlsScreen> createState() =>
      _RadioControlsScreenState();
}

class _RadioControlsScreenState extends ConsumerState<RadioControlsScreen> {
  /// Preserved verbatim from `lib/features/ptt/emg_key.dart`'s
  /// `armThreshold` default — Design §2.5/UX-D06 requires the *existing*
  /// hold duration, not a re-chosen one.
  static const Duration emergencyHoldDuration = Duration(milliseconds: 600);

  StreamSubscription<RadioHostSnapshot>? _hostSub;
  StreamSubscription<FloorEffect>? _floorSub;
  late RadioHostSnapshot _snapshot;
  Timer? _emergencyArmTimer;
  bool _emergencyArming = false;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.host.current;
    _hostSub = widget.host.changes.listen(_onSnapshot);
    _subscribeFloor(_snapshot.floorEngine);
  }

  @override
  void dispose() {
    _emergencyArmTimer?.cancel();
    unawaited(_hostSub?.cancel());
    unawaited(_floorSub?.cancel());
    super.dispose();
  }

  void _onSnapshot(RadioHostSnapshot snapshot) {
    if (!mounted) return;
    final bool engineChanged = !identical(
      snapshot.floorEngine,
      _snapshot.floorEngine,
    );
    setState(() => _snapshot = snapshot);
    if (engineChanged) _subscribeFloor(snapshot.floorEngine);
  }

  /// Emergency pin/clear is engine-owned state with no independent change
  /// stream of its own except [FloorEngine.effects] — a *remote* peer
  /// pinning/clearing emergency must still update this screen's authoritative
  /// indicator (UX-FR-043: "never from local widget state"), not just a
  /// locally-initiated arm/clear.
  void _subscribeFloor(FloorEngine? engine) {
    unawaited(_floorSub?.cancel());
    _floorSub = engine?.effects.listen(_onFloorEffect);
  }

  void _onFloorEffect(FloorEffect effect) {
    if (!mounted) return;
    if (effect is EmgPinned || effect is EmgCleared) setState(() {});
  }

  bool get _radioOperational =>
      !_snapshot.micPermissionDenied && _snapshot.serviceFaultMessage == null;

  /// Monitor/Scan are only meaningful once the radio has actually booted
  /// and while it is not mid-transmit/mid-tune — the same "authoritative
  /// eligibility" UX-FR-041 asks for, driven off `RadioState.phase`, never
  /// a locally-invented flag.
  bool _eligible(RadioState state) {
    if (!_radioOperational) return false;
    switch (state.phase) {
      case RadioPhase.off:
      case RadioPhase.boot:
      case RadioPhase.tuning:
      case RadioPhase.txRequest:
      case RadioPhase.tx:
        return false;
      case RadioPhase.idle:
      case RadioPhase.rxActive:
      case RadioPhase.linkDegraded:
        return true;
    }
  }

  void _dispatch(RadioEvent event) =>
      ref.read(radioStateProvider.notifier).dispatch(event);

  void _monitorHoldStart(RadioState state) {
    if (!_eligible(state)) return;
    _dispatch(const MonitorChanged(true));
  }

  void _monitorHoldEnd(RadioState state) {
    if (!state.isMonitorOpen) return;
    _dispatch(const MonitorChanged(false));
  }

  void _toggleScan(RadioState state) {
    if (!_eligible(state)) return;
    _dispatch(ScanChanged(!state.isScanning));
  }

  void _startEmergencyArm() {
    if (_emergencyArming || _snapshot.floorEngine == null) return;
    setState(() => _emergencyArming = true);
    _emergencyArmTimer = Timer(emergencyHoldDuration, _activateEmergency);
  }

  void _cancelEmergencyArm() {
    _emergencyArmTimer?.cancel();
    _emergencyArmTimer = null;
    if (_emergencyArming) setState(() => _emergencyArming = false);
  }

  /// Identical branch to `face_screen.dart._onEmergencyToggled`'s existing
  /// grant path — never rewritten, only relocated.
  void _activateEmergency() {
    _emergencyArmTimer = null;
    if (!mounted) return;
    final FloorEngine? engine = _snapshot.floorEngine;
    engine?.requestTransmit(emergency: true);
    // A single setState covers both the arm-flag reset and picking up the
    // engine's now-updated isEmergencyPinned/emergencyPeer for this build —
    // the engine itself has no independent change stream to listen to.
    setState(() => _emergencyArming = false);
  }

  /// Identical branch to `face_screen.dart._onEmergencyToggled`'s existing
  /// clear path — owner-only, exactly as `FloorEngine.clearEmergency`
  /// already enforces.
  void _clearEmergency() {
    final FloorEngine? engine = _snapshot.floorEngine;
    if (engine == null) return;
    if (engine.isEmergencyPinned && engine.emergencyPeer == engine.localPeerId) {
      engine.clearEmergency();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    final RadioState radioState = ref.watch(radioStateProvider);
    final FloorEngine? engine = _snapshot.floorEngine;
    final bool emergencyPinned = engine?.isEmergencyPinned ?? false;
    final bool emergencyOwnedByLocal =
        emergencyPinned && engine?.emergencyPeer == engine?.localPeerId;

    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(
        title: Text(
          RadioControlsCopy.title,
          key: RadioControlsKeys.title,
          style: KeryxUxTypography.screenTitle.copyWith(
            color: tokens.textPrimary,
          ),
        ),
        backgroundColor: tokens.surfaceBase,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
        children: <Widget>[
          _MonitorRow(
            tokens: tokens,
            active: radioState.isMonitorOpen,
            eligible: _eligible(radioState),
            onHoldStart: () => _monitorHoldStart(radioState),
            onHoldEnd: () => _monitorHoldEnd(radioState),
          ),
          const SizedBox(height: KeryxUxSpacing.cardSpacing),
          _ScanRow(
            tokens: tokens,
            active: radioState.isScanning,
            eligible: _eligible(radioState),
            onTap: () => _toggleScan(radioState),
          ),
          const SizedBox(height: KeryxUxSpacing.cardSpacing),
          _EmergencyRow(
            tokens: tokens,
            pinned: emergencyPinned,
            ownedByLocal: emergencyOwnedByLocal,
            arming: _emergencyArming,
            engineAvailable: engine != null,
            onArmStart: _startEmergencyArm,
            onArmCancel: _cancelEmergencyArm,
            onClear: _clearEmergency,
          ),
        ],
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.tokens, required this.child});

  final KeryxUxTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KeryxUxSpacing.cardSpacing),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.borderDefault),
      ),
      child: child,
    );
  }
}

class _UnavailableExplanation extends StatelessWidget {
  const _UnavailableExplanation({
    required this.tokens,
    required this.text,
    required this.itemKey,
  });

  final KeryxUxTokens tokens;
  final String text;
  final Key itemKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: itemKey,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.info_outline, size: 16, color: tokens.stateWarning),
        const SizedBox(width: KeryxUxSpacing.controlGap),
        Flexible(
          child: Text(
            text,
            style: KeryxUxTypography.secondary.copyWith(
              color: tokens.stateWarning,
            ),
          ),
        ),
      ],
    );
  }
}

class _MonitorRow extends StatelessWidget {
  const _MonitorRow({
    required this.tokens,
    required this.active,
    required this.eligible,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final KeryxUxTokens tokens;
  final bool active;
  final bool eligible;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return _ControlCard(
      tokens: tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            key: RadioControlsKeys.monitorRow,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      RadioControlsCopy.monitorLabel,
                      style: KeryxUxTypography.sectionTitle.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      RadioControlsCopy.monitorDescription,
                      style: KeryxUxTypography.secondary.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                key: RadioControlsKeys.monitorIndicator,
                Icons.hearing,
                color: active ? tokens.stateRx : tokens.textSecondary,
              ),
              const SizedBox(width: KeryxUxSpacing.controlGap),
              Listener(
                key: RadioControlsKeys.monitorHoldTarget,
                onPointerDown: eligible ? (_) => onHoldStart() : null,
                onPointerUp: eligible ? (_) => onHoldEnd() : null,
                onPointerCancel: eligible ? (_) => onHoldEnd() : null,
                child: Container(
                  width: KeryxUxSpacing.minTarget,
                  height: KeryxUxSpacing.minTarget,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? tokens.stateRx : tokens.surfaceRaised,
                    border: Border.all(
                      color: eligible
                          ? tokens.borderDefault
                          : tokens.borderDefault.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    Icons.radio_button_on,
                    color: eligible
                        ? tokens.palette.contrastingOn(
                            active ? tokens.stateRx : tokens.surfaceRaised,
                          )
                        : tokens.textSecondary.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
          if (!eligible) ...<Widget>[
            const SizedBox(height: KeryxUxSpacing.controlGap),
            _UnavailableExplanation(
              tokens: tokens,
              itemKey: RadioControlsKeys.monitorUnavailable,
              text: RadioControlsCopy.controlUnavailableBusy,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({
    required this.tokens,
    required this.active,
    required this.eligible,
    required this.onTap,
  });

  final KeryxUxTokens tokens;
  final bool active;
  final bool eligible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ControlCard(
      tokens: tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            key: RadioControlsKeys.scanRow,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      RadioControlsCopy.scanLabel,
                      style: KeryxUxTypography.sectionTitle.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      RadioControlsCopy.scanDescription,
                      style: KeryxUxTypography.secondary.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                key: RadioControlsKeys.scanIndicator,
                Icons.search,
                color: active ? tokens.stateRx : tokens.textSecondary,
              ),
              const SizedBox(width: KeryxUxSpacing.controlGap),
              Switch(
                key: RadioControlsKeys.scanSwitch,
                value: active,
                onChanged: eligible ? (_) => onTap() : null,
                activeThumbColor: tokens.stateRx,
              ),
            ],
          ),
          if (!eligible) ...<Widget>[
            const SizedBox(height: KeryxUxSpacing.controlGap),
            _UnavailableExplanation(
              tokens: tokens,
              itemKey: RadioControlsKeys.scanUnavailable,
              text: RadioControlsCopy.controlUnavailableBusy,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmergencyRow extends StatelessWidget {
  const _EmergencyRow({
    required this.tokens,
    required this.pinned,
    required this.ownedByLocal,
    required this.arming,
    required this.engineAvailable,
    required this.onArmStart,
    required this.onArmCancel,
    required this.onClear,
  });

  final KeryxUxTokens tokens;
  final bool pinned;
  final bool ownedByLocal;
  final bool arming;
  final bool engineAvailable;
  final VoidCallback onArmStart;
  final VoidCallback onArmCancel;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final Color emergencyColor = tokens.stateEmergency;
    return Container(
      key: RadioControlsKeys.emergencyRow,
      padding: const EdgeInsets.all(KeryxUxSpacing.cardSpacing),
      decoration: BoxDecoration(
        color: pinned
            ? emergencyColor.withValues(alpha: 0.15)
            : tokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: emergencyColor, width: pinned ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: emergencyColor),
              const SizedBox(width: KeryxUxSpacing.controlGap),
              Expanded(
                child: Text(
                  RadioControlsCopy.emergencyLabel,
                  style: KeryxUxTypography.sectionTitle.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              if (pinned)
                Text(
                  RadioControlsCopy.emergencyActiveBanner,
                  key: RadioControlsKeys.emergencyBanner,
                  style: KeryxUxTypography.secondary.copyWith(
                    color: emergencyColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: KeryxUxSpacing.controlGap),
          Text(
            RadioControlsCopy.emergencyDescription,
            style: KeryxUxTypography.secondary.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: KeryxUxSpacing.cardSpacing),
          if (!engineAvailable)
            _UnavailableExplanation(
              tokens: tokens,
              itemKey: RadioControlsKeys.emergencyUnavailable,
              text: RadioControlsCopy.controlUnavailableNoEngine,
            )
          else if (pinned)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!ownedByLocal)
                  Padding(
                    padding: const EdgeInsets.only(
                      bottom: KeryxUxSpacing.controlGap,
                    ),
                    child: _UnavailableExplanation(
                      tokens: tokens,
                      itemKey: RadioControlsKeys.emergencyClearedByOther,
                      text: RadioControlsCopy.emergencyClearedByOwnerOnly,
                    ),
                  ),
                FilledButton(
                  key: RadioControlsKeys.emergencyClear,
                  onPressed: ownedByLocal ? onClear : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: emergencyColor,
                    foregroundColor: tokens.palette.contrastingOn(emergencyColor),
                  ),
                  child: Text(RadioControlsCopy.emergencyClearAction),
                ),
              ],
            )
          else
            Listener(
              key: RadioControlsKeys.emergencyHoldTarget,
              onPointerDown: (_) => onArmStart(),
              onPointerUp: (_) => onArmCancel(),
              onPointerCancel: (_) => onArmCancel(),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: KeryxUxSpacing.cardSpacing,
                  vertical: KeryxUxSpacing.controlGap,
                ),
                decoration: BoxDecoration(
                  color: arming ? emergencyColor : tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: emergencyColor),
                ),
                constraints: const BoxConstraints(
                  minHeight: KeryxUxSpacing.minTarget,
                ),
                alignment: Alignment.center,
                child: Text(
                  arming
                      ? RadioControlsCopy.emergencyArmingHint
                      : RadioControlsCopy.emergencyLabel,
                  key: arming ? RadioControlsKeys.emergencyArming : null,
                  style: KeryxUxTypography.body.copyWith(
                    color: arming
                        ? tokens.palette.contrastingOn(emergencyColor)
                        : emergencyColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
