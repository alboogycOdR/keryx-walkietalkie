import 'package:flutter/material.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/display/display.dart';
import 'package:keryx/features/grille/grille.dart';
import 'package:keryx/features/knob/knob.dart';
import 'package:keryx/features/ptt/ptt.dart';
import 'package:keryx/features/tuning/tuning.dart';

import 'glass_flip_controller.dart';
import 'housing.dart';
import 'roster.dart';
import 'station_panel.dart';
import 'status_strip.dart';

/// Pure-presentation composition of the whole radio face, per DS §4's
/// vertical allocation and TS §6.1's face diagram.
///
/// EVERY value this widget renders is either passed in directly or derived
/// by a pure function of what was passed in — it holds no `State` of its
/// own for anything [RadioState] already owns (phase/mode/channel/etc.).
/// [FaceScreen] is the sole place that reads [RadioState] and calls
/// `dispatch`; this widget only forwards intents outward via callbacks, per
/// TS §8.2 ("UI … are all projections of it").
class FaceView extends StatelessWidget {
  const FaceView({
    super.key,
    required this.state,
    required this.stations,
    required this.amplitude,
    required this.flipController,
    required this.pttState,
    required this.batteryLevel,
    required this.onDetent,
    required this.onStep,
    required this.onDirectTuneRequested,
    required this.onRecallRequested,
    required this.onPttPressStart,
    required this.onPttPressEnd,
    required this.onLatchToggled,
    required this.onMonHoldStart,
    required this.onMonHoldEnd,
    required this.onScan,
    required this.onSayAgain,
    required this.onSettings,
    required this.onEmergencyToggled,
    this.onScanQr,
    this.onExportQr,
    this.statusOverride,
  });

  final RadioState state;
  final List<StationInfo> stations;
  final Stream<double> amplitude;
  final GlassFlipController flipController;
  final PttState pttState;
  final double batteryLevel;

  final KnobDetentCallback onDetent;
  final ChannelStepCallback onStep;
  final VoidCallback onDirectTuneRequested;
  final VoidCallback onRecallRequested;
  final VoidCallback onPttPressStart;
  final VoidCallback onPttPressEnd;
  final ValueChanged<bool> onLatchToggled;
  final VoidCallback onMonHoldStart;
  final VoidCallback onMonHoldEnd;
  final VoidCallback onScan;
  final VoidCallback onSayAgain;
  final VoidCallback onSettings;
  final VoidCallback onEmergencyToggled;

  /// FR-043/FR-044 Event QR entry points, surfaced as two small icon
  /// buttons in [StationListPanel]'s header — that panel is already the
  /// face's natural "flip to a secondary screen" home (FR-067's station
  /// list), so it is where a scan/export affordance reads as belonging,
  /// rather than adding a seventh DS §4 band or overloading an existing
  /// PTT-row key. `null` disables the corresponding button (e.g. no
  /// session yet to `joinEvent` into).
  final VoidCallback? onScanQr;
  final VoidCallback? onExportQr;

  /// TASK-038: a non-modal, on-face telltale line for a condition
  /// [RadioState] itself has no field for — a denied `RECORD_AUDIO`
  /// permission, or a foreground-service fault (`RadioServiceFailed`) —
  /// per FR-045's "never a modal" rule. `FaceScreen` computes this locally
  /// (both conditions live outside the frozen `lib/core/state` reducer,
  /// out of this task's `Owned_Paths`) and it takes priority over
  /// [_statusLine]'s own [RadioState]-derived text when non-null; `null`
  /// (the default) leaves the glass showing exactly what it always did.
  final String? statusOverride;

  static const int _flexScale = 1000;

  /// Stable keys for the six DS §4 bands — used by widget tests to locate
  /// each band's [Expanded] precisely, since several child widgets
  /// (`PttKeyRow`, `KeryxLcdDisplay`) contain their own internal `Expanded`s.
  static const Key bandKeyStatus = Key('keryx-face-band-status');
  static const Key bandKeyGlass = Key('keryx-face-band-glass');
  static const Key bandKeyGrille = Key('keryx-face-band-grille');
  static const Key bandKeyControls = Key('keryx-face-band-controls');
  static const Key bandKeyPtt = Key('keryx-face-band-ptt');
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
    final telltales = <KeryxTelltale>{
      if (state.phase == RadioPhase.tx) KeryxTelltale.tx,
      if (state.isMonitorOpen) KeryxTelltale.mon,
      if (state.isPrivate) KeryxTelltale.prv,
      if (state.isVoxArmed) KeryxTelltale.vox,
      if (state.isEmergency) KeryxTelltale.emg,
      if (state.isNoLink) KeryxTelltale.noLink,
      if (state.isReplay) KeryxTelltale.replay,
    };
    return KeryxDisplayModel.numbered(
      channel: state.channel,
      code: state.privacyCode,
      modeLabel: state.mode.name.toUpperCase(),
      statusLine: _statusLine(),
      telltales: telltales,
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

  /// [KeryxLcdDisplay]'s content (`lib/features/display/**`, outside this
  /// task's `Owned_Paths`) needs roughly this much room at its own internal
  /// text scale — more than DS §4's 18% glass band actually provides on
  /// several realistic phone sizes (its `Column` isn't itself scroll/clip
  /// safe). `FittedBox` + a fixed "natural" box lets it lay out at a size
  /// it's happy with, then scales the whole result down to whatever the
  /// glass band actually has — the composition-layer guarantee "app boots
  /// to the face" (this task's own acceptance criterion) needs, without
  /// editing the display widget itself.
  static const double _glassNaturalWidth = 340;
  static const double _glassNaturalHeight = 280;

  Widget _glassRegion() {
    return GlassFlipper(
      controller: flipController,
      front: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: _glassNaturalWidth,
          height: _glassNaturalHeight,
          child: KeryxLcdDisplay(model: _displayModel()),
        ),
      ),
      back: StationListPanel(
        stations: stations,
        onScan: onScanQr,
        onExport: onExportQr,
        // Review round-1 finding (b): keep FR-043's scan/export entry
        // points reachable under the auto-flip window instead of only
        // inside a fixed 5 s from the STN tap — see
        // `StationListPanel.onInteraction`'s dartdoc.
        onInteraction: flipController.flipToStations,
      ),
    );
  }

  Widget _statusStripRegion() {
    return StatusStrip(
      stationCount: state.stationCount,
      signalQuality: aggregateSignalQuality(
        stations: stations,
        activeSpeakerPeerId: state.activeSpeaker,
      ),
      modeLabel: state.mode.name.toUpperCase(),
      batteryLevel: batteryLevel,
      onStationsTap: flipController.flipToStations,
    );
  }

  Widget _grilleRegion() {
    return KeryxSpeakerGrille(
      amplitude: amplitude,
      live: state.phase == RadioPhase.rxActive || state.activeSpeaker != null,
    );
  }

  /// Knob + CH▲/▼ steppers. Controls band per DS §4 — "never occupy the top
  /// third", which the portrait/landscape allocations below guarantee
  /// structurally (status+glass+grille = 50% of the stack always precede
  /// this region).
  Widget _controlsRegion() {
    final enabled = state.phase != RadioPhase.off && state.phase != RadioPhase.boot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KeryxTheme.grid),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          // The knob (96px) + two 54px steppers don't fit the controls
          // band's own width when it's the narrow slice of a landscape
          // Row (DS §4's fractions were sized against the portrait Column,
          // where this band gets the full face width) — FittedBox keeps
          // the trio intact and legible instead of overflowing the band,
          // and is a no-op in portrait where the row already fits.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                ChStepperButton(
                  direction: StepDirection.down,
                  channel: state.channel,
                  onStep: onStep,
                  onLongPress: onRecallRequested,
                  enabled: enabled,
                  semanticsLabel: 'Channel down',
                ),
                GestureDetector(
                  onLongPress: onDirectTuneRequested,
                  child: KeryxTuningKnob(
                    channel: state.channel,
                    onDetent: onDetent,
                    enabled: enabled,
                  ),
                ),
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
          const SizedBox(height: KeryxTheme.grid),
          PttKeyRow(
            onMonHoldStart: onMonHoldStart,
            onMonHoldEnd: onMonHoldEnd,
            onScan: onScan,
            onSayAgain: onSayAgain,
            onSettings: onSettings,
            enabled: enabled,
          ),
        ],
      ),
    );
  }

  Widget _pttRegion() {
    final enabled = state.phase != RadioPhase.off && state.phase != RadioPhase.boot;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KeryxTheme.grid),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          PttEdgeGlow(
            active: state.phase == RadioPhase.tx,
            child: PttButton(
              state: pttState,
              enabled: enabled,
              onPressStart: onPttPressStart,
              onPressEnd: onPttPressEnd,
              onLatchToggled: onLatchToggled,
            ),
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
}

/// Portrait — primary orientation (TS §6.1): status strip / glass / grille /
/// controls / PTT / safe area, stacked top-to-bottom exactly per DS §4's
/// six-band allocation.
class _PortraitBody extends StatelessWidget {
  const _PortraitBody({required this.view});

  final FaceView view;

  @override
  Widget build(BuildContext context) {
    final a = KeryxTheme.faceAllocation;
    return Column(
      children: <Widget>[
        Expanded(
          key: FaceView.bandKeyStatus,
          flex: (a.status * FaceView._flexScale).round(),
          child: view._statusStripRegion(),
        ),
        Expanded(
          key: FaceView.bandKeyGlass,
          flex: (a.glass * FaceView._flexScale).round(),
          child: Padding(
            padding: const EdgeInsets.all(KeryxTheme.grid),
            child: view._glassRegion(),
          ),
        ),
        Expanded(
          key: FaceView.bandKeyGrille,
          flex: (a.grille * FaceView._flexScale).round(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: KeryxTheme.grid),
            child: view._grilleRegion(),
          ),
        ),
        Expanded(
          key: FaceView.bandKeyControls,
          flex: (a.controls * FaceView._flexScale).round(),
          child: view._controlsRegion(),
        ),
        Expanded(
          key: FaceView.bandKeyPtt,
          flex: (a.ptt * FaceView._flexScale).round(),
          child: view._pttRegion(),
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
/// same six bands, same order and same proportions, laid out left-to-right
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
          key: FaceView.bandKeyStatus,
          flex: (a.status * FaceView._flexScale).round(),
          child: RotatedBox(quarterTurns: 3, child: view._statusStripRegion()),
        ),
        Expanded(
          key: FaceView.bandKeyGlass,
          flex: (a.glass * FaceView._flexScale).round(),
          child: Padding(
            padding: const EdgeInsets.all(KeryxTheme.grid),
            child: view._glassRegion(),
          ),
        ),
        Expanded(
          key: FaceView.bandKeyGrille,
          flex: (a.grille * FaceView._flexScale).round(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: KeryxTheme.grid),
            child: view._grilleRegion(),
          ),
        ),
        Expanded(
          key: FaceView.bandKeyControls,
          flex: (a.controls * FaceView._flexScale).round(),
          child: view._controlsRegion(),
        ),
        Expanded(
          key: FaceView.bandKeyPtt,
          flex: (a.ptt * FaceView._flexScale).round(),
          child: view._pttRegion(),
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
