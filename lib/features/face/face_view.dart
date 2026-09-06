import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/display/display.dart';
import 'package:keryx/features/ptt/ptt.dart';
import 'package:keryx/features/tuning/tuning.dart';

import 'housing.dart';
import 'roster.dart';
import 'status_strip.dart';

/// Pure-presentation composition of the whole radio face, per the approved
/// Phase 2 design canvas (Main.dc.html): header/status -> LCD strip ->
/// (optional emergency band) -> hero PTT disc -> four-key rail.
///
/// TASK-043 retires the knob+glass-flip+grille+control-cluster layout
/// (TASK-041/042's territory shipped their replacements) in favour of this
/// composition. EVERY value this widget renders is either passed in
/// directly or derived by a pure function of what was passed in — it holds
/// no `State` of its own for anything [RadioState] already owns
/// (phase/mode/channel/etc.). [FaceScreen] is the sole place that reads
/// [RadioState] and calls `dispatch`; this widget only forwards intents
/// outward via callbacks, per TS §8.2 ("UI … are all projections of it").
class FaceView extends StatelessWidget {
  const FaceView({
    super.key,
    required this.state,
    required this.stations,
    required this.ringLevel,
    required this.pttState,
    required this.batteryLevel,
    required this.onStep,
    required this.onDirectTuneRequested,
    required this.onRecallRequested,
    required this.onPttPressStart,
    required this.onPttPressEnd,
    required this.onLatchToggled,
    required this.onMonHoldStart,
    required this.onMonHoldEnd,
    required this.onScan,
    required this.onOpenRoster,
    required this.onSettings,
    required this.onEmergencyToggled,
    this.onScanQr,
    this.onExportQr,
    this.statusOverride,
  });

  final RadioState state;
  final List<StationInfo> stations;

  /// 0-100 amplitude feeding the hero disc's ring meter — see
  /// `FaceScreen._ringLevelFor`'s dartdoc for the TX/RX/proxy split.
  final ValueListenable<double> ringLevel;

  final PttState pttState;
  final double batteryLevel;

  final ChannelStepCallback onStep;
  final VoidCallback onDirectTuneRequested;
  final VoidCallback onRecallRequested;
  final VoidCallback onPttPressStart;
  final VoidCallback onPttPressEnd;
  final ValueChanged<bool> onLatchToggled;
  final VoidCallback onMonHoldStart;
  final VoidCallback onMonHoldEnd;
  final VoidCallback onScan;

  /// STN key / status-strip tap — opens the full-screen roster (FR-067's
  /// successor; no more flip panel).
  final VoidCallback onOpenRoster;

  final VoidCallback onSettings;
  final VoidCallback onEmergencyToggled;

  /// FR-043/FR-044 Event QR entry points. Surfaced on the roster screen
  /// (`RosterScreen`'s own header — see `FaceScreen._openRoster`), not here;
  /// kept on [FaceView] only so `FaceScreen` can pass them straight through
  /// without this widget needing to know about `RosterScreen`'s internals.
  /// `null` disables the corresponding affordance (e.g. no session yet).
  final VoidCallback? onScanQr;
  final VoidCallback? onExportQr;

  /// TASK-038: a non-modal, on-face telltale line for a condition
  /// [RadioState] itself has no field for — a denied `RECORD_AUDIO`
  /// permission, or a foreground-service fault (`RadioServiceFailed`) —
  /// per FR-045's "never a modal" rule. `FaceScreen` computes this locally
  /// and it takes priority over [_statusLine]'s own [RadioState]-derived
  /// text when non-null; `null` (the default) leaves the glass showing
  /// exactly what it always did.
  final String? statusOverride;

  static const int _flexScale = 1000;

  /// Stable keys for the face's stacked bands — used by widget tests to
  /// locate each band's [Expanded] precisely.
  static const Key bandKeyHeader = Key('keryx-face-band-header');
  static const Key bandKeyDisplay = Key('keryx-face-band-display');
  static const Key bandKeyEmergency = Key('keryx-face-band-emergency');
  static const Key bandKeySteppers = Key('keryx-face-band-steppers');
  static const Key bandKeyDisc = Key('keryx-face-band-disc');
  static const Key bandKeyRail = Key('keryx-face-band-rail');
  static const Key bandKeySafeArea = Key('keryx-face-band-safe-area');

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.orientationOf(context);
    final content = orientation == Orientation.landscape
        ? _LandscapeBody(view: this)
        : _PortraitBody(view: this);
    return KeryxHousing(
      child: SafeArea(
        child: Semantics(
          container: true,
          label: 'Keryx radio face',
          child: content,
        ),
      ),
    );
  }

  KeryxDisplayModel _displayModel() {
    final telltales = <KeryxStripTelltale>{
      if (state.mode == RadioMode.local || state.mode == RadioMode.auto)
        KeryxStripTelltale.local,
      if (state.mode == RadioMode.linked) KeryxStripTelltale.linked,
      if (state.phase == RadioPhase.tx) KeryxStripTelltale.tx,
      if (state.phase == RadioPhase.rxActive) KeryxStripTelltale.rx,
    };
    return KeryxDisplayModel(
      channel: state.channel,
      mode: state.mode.name.toUpperCase(),
      telltales: telltales,
      statusLine: _statusLine(),
      signalQuality: aggregateSignalQuality(
            stations: stations,
            activeSpeakerPeerId: state.activeSpeaker,
          ) ??
          0,
      isBooting: state.phase == RadioPhase.off || state.phase == RadioPhase.boot,
      dimLevel: state.phase == RadioPhase.off ? 0.3 : 1,
    );
  }

  String _statusLine() {
    if (statusOverride != null) return statusOverride!;
    if (state.isTransmitDenied) return 'DENIED';
    if (state.phase == RadioPhase.txRequest) return 'REQUESTING';
    if (state.phase == RadioPhase.tx) {
      return state.isTotWarning ? 'TX · T-5S' : 'TRANSMITTING';
    }
    if (state.isScanning) return 'SCANNING';
    if (state.activeSpeaker != null) return 'RECEIVING';
    if (state.isNoLink) return 'NO LINK';
    return 'CHANNEL CLEAR';
  }

  Widget _headerRegion() {
    return StatusStrip(
      stationCount: state.stationCount,
      signalQuality: aggregateSignalQuality(
        stations: stations,
        activeSpeakerPeerId: state.activeSpeaker,
      ),
      modeLabel: state.mode.name.toUpperCase(),
      batteryLevel: batteryLevel,
      onStationsTap: onOpenRoster,
      onSettingsTap: onSettings,
    );
  }

  /// [KeryxLcdDisplay]'s content needs roughly this much room at its own
  /// internal text scale — more than the display band actually provides on
  /// several realistic phone sizes (its `Column`/`Row`s aren't themselves
  /// scroll/clip safe). `FittedBox` + a fixed "natural" box lets it lay out
  /// at a size it's happy with, then scales the whole result down to
  /// whatever the band actually has, same technique the pre-Phase-2 glass
  /// region used for the full-size display.
  static const double _stripNaturalWidth = 320;
  static const double _stripNaturalHeight = 96;

  Widget _displayRegion() {
    return Padding(
      padding: const EdgeInsets.all(KeryxTheme.grid),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: _stripNaturalWidth,
          height: _stripNaturalHeight,
          child: KeryxLcdDisplay(model: _displayModel()),
        ),
      ),
    );
  }

  /// Emergency.dc.html's hard orange band — rendered only while
  /// [RadioState.isEmergency] is true, per this task's own acceptance
  /// criterion. `SizedBox.shrink()` (not a conditional child) so the band's
  /// [Key] is always present for widget tests to assert absence against.
  Widget _emergencyRegion() {
    if (!state.isEmergency) return const SizedBox.shrink();
    // No `width: double.infinity` — this band sits directly in the
    // portrait `Column`/landscape `Row` alongside `Expanded` siblings with
    // no `Expanded` of its own (its natural height/width should not eat
    // into the flex allocation), so an infinite-extent child would hit an
    // unbounded-constraint layout error in the landscape `Row` case. A
    // `ColoredBox` at `Alignment.center`'s natural text width still reads
    // as a hard band across the face in both orientations.
    return ColoredBox(
      key: const Key('keryx-emergency-band'),
      color: KeryxTheme.emergency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
        child: Text(
          'EMERGENCY ACTIVE',
          textAlign: TextAlign.center,
          style: KeryxTheme.legendLabel.copyWith(color: KeryxTheme.shell900),
        ),
      ),
    );
  }

  /// CH▼/▲ steppers — the knob's replacement per the approved canvas
  /// (which has no rotary control). Long-press-down opens channel recall;
  /// long-press-up is unused (matches the pre-Phase-2 assignment).
  Widget _steppersRegion() {
    final enabled = state.phase != RadioPhase.off && state.phase != RadioPhase.boot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KeryxTheme.grid),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ChStepperButton(
              direction: StepDirection.down,
              channel: state.channel,
              onStep: onStep,
              onLongPress: onRecallRequested,
              enabled: enabled,
              semanticsLabel: 'Channel down',
            ),
            const SizedBox(width: KeryxTheme.grid * 3),
            GestureDetector(
              onLongPress: onDirectTuneRequested,
              child: Text(
                'CH ${state.channel.toString().padLeft(2, '0')}',
                style: KeryxTheme.panelBody.copyWith(color: KeryxTheme.legend),
              ),
            ),
            const SizedBox(width: KeryxTheme.grid * 3),
            ChStepperButton(
              direction: StepDirection.up,
              channel: state.channel,
              onStep: onStep,
              enabled: enabled,
              semanticsLabel: 'Channel up',
            ),
          ],
        ),
      ),
    );
  }

  /// Hero disc + EMG side key, per the approved canvas's Main/Transmit/
  /// Receive/Emergency artboards.
  Widget _discRegion() {
    final enabled = state.phase != RadioPhase.off && state.phase != RadioPhase.boot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KeryxTheme.grid),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          PttButton(
            state: pttState,
            enabled: enabled,
            ringController: ringLevel,
            onPressStart: onPttPressStart,
            onPressEnd: onPttPressEnd,
            onLatchToggled: onLatchToggled,
          ),
          Positioned(
            right: -4,
            top: 0,
            bottom: 0,
            child: Align(
              child: EmgKey(
                onEmergencyToggled: onEmergencyToggled,
                pinned: state.isEmergency,
                enabled: enabled,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The Phase 2 four-key rail (MON/SCAN/STN/EMG). `key_row.dart`'s
  /// callback names remain source-compatible with the pre-Phase-2 rail
  /// (see its own dartdoc) — `onSayAgain` is wired to the STN-labelled key
  /// (opens the roster) and `onSettings` is wired to the EMG-labelled key
  /// (fires the same emergency intent as the disc's side key, reusing
  /// `emg_key.dart`'s existing signal rather than inventing a second one).
  /// Real Settings access moves to [_headerRegion]'s kebab affordance per
  /// the approved canvas's header placement.
  Widget _railRegion() {
    final enabled = state.phase != RadioPhase.off && state.phase != RadioPhase.boot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KeryxTheme.grid),
      child: PttKeyRow(
        onMonHoldStart: onMonHoldStart,
        onMonHoldEnd: onMonHoldEnd,
        onScan: onScan,
        onSayAgain: onOpenRoster,
        onSettings: onEmergencyToggled,
        enabled: enabled,
      ),
    );
  }
}

/// Portrait — primary orientation (TS §6.1): header / display / (emergency
/// band) / steppers / disc / rail / safe area, stacked top-to-bottom.
class _PortraitBody extends StatelessWidget {
  const _PortraitBody({required this.view});

  final FaceView view;

  @override
  Widget build(BuildContext context) {
    final a = KeryxTheme.faceAllocation;
    return Column(
      children: <Widget>[
        Expanded(
          key: FaceView.bandKeyHeader,
          flex: (a.status * FaceView._flexScale).round(),
          child: view._headerRegion(),
        ),
        Expanded(
          key: FaceView.bandKeyDisplay,
          flex: (a.glass * FaceView._flexScale).round(),
          child: view._displayRegion(),
        ),
        KeyedSubtree(
          key: FaceView.bandKeyEmergency,
          child: view._emergencyRegion(),
        ),
        Expanded(
          key: FaceView.bandKeySteppers,
          flex: (a.grille * FaceView._flexScale).round(),
          child: view._steppersRegion(),
        ),
        Expanded(
          key: FaceView.bandKeyDisc,
          flex: (a.controls * FaceView._flexScale).round(),
          child: Center(child: view._discRegion()),
        ),
        Expanded(
          key: FaceView.bandKeyRail,
          flex: (a.ptt * FaceView._flexScale).round(),
          child: view._railRegion(),
        ),
        Expanded(
          key: FaceView.bandKeySafeArea,
          flex: (a.safeArea * FaceView._flexScale).round(),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Landscape — "the radio rotates to 'brick on its side'" (TS §6.1): the
/// same bands, same order and same proportions, laid out left-to-right
/// instead of top-to-bottom so the device is read the same way rotated.
class _LandscapeBody extends StatelessWidget {
  const _LandscapeBody({required this.view});

  final FaceView view;

  @override
  Widget build(BuildContext context) {
    final a = KeryxTheme.faceAllocation;
    return Row(
      children: <Widget>[
        Expanded(
          key: FaceView.bandKeyHeader,
          flex: (a.status * FaceView._flexScale).round(),
          child: RotatedBox(quarterTurns: 3, child: view._headerRegion()),
        ),
        Expanded(
          key: FaceView.bandKeyDisplay,
          flex: (a.glass * FaceView._flexScale).round(),
          child: view._displayRegion(),
        ),
        KeyedSubtree(
          key: FaceView.bandKeyEmergency,
          child: view._emergencyRegion(),
        ),
        Expanded(
          key: FaceView.bandKeySteppers,
          flex: (a.grille * FaceView._flexScale).round(),
          child: view._steppersRegion(),
        ),
        Expanded(
          key: FaceView.bandKeyDisc,
          flex: (a.controls * FaceView._flexScale).round(),
          child: Center(child: view._discRegion()),
        ),
        Expanded(
          key: FaceView.bandKeyRail,
          flex: (a.ptt * FaceView._flexScale).round(),
          child: view._railRegion(),
        ),
        Expanded(
          key: FaceView.bandKeySafeArea,
          flex: (a.safeArea * FaceView._flexScale).round(),
          child: const SizedBox.shrink(),
        ),
      ],
    );
  }
}
