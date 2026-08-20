import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/ptt/ptt_haptics.dart';
import 'package:keryx/features/ptt/ptt_state.dart';

/// The hero push-to-talk surface (TS §6.1, §6.4; FR-020/021/022/026).
///
/// Pure presentation + intent — this widget owns no floor state. [state] is
/// externally driven (see `ptt_state.dart`'s library dartdoc for the
/// caller/`FloorEngine` relationship); this widget only decides how to
/// *render* a given state and which gesture intents to emit for a caller to
/// turn into `FloorEngine.requestTransmit()` / `.releaseTransmit()` calls.
///
/// **Gesture contract** (FR-020 hold-to-talk, FR-021 latch mode):
/// - A plain press-and-release calls [onPressStart] on pointer-down and
///   [onPressEnd] on pointer-up/cancel — the default hold-to-talk path.
/// - When [latchEnabled] and the second pointer-down of a rapid double-tap
///   arrives (within [doubleTapWindow], defaulting to Flutter's own
///   `kDoubleTapTimeout` — PT has no latch implementation at all to source a
///   ratified figure from, see below), [onLatchToggled] fires with `true`
///   instead of [onPressStart]/[onPressEnd] for that gesture.
/// - While [state] is [PttState.latched], any tap fires [onLatchToggled]
///   with `false` (release) instead of the hold-to-talk callbacks.
///
/// This widget deliberately uses raw pointer callbacks (`Listener`), not
/// `GestureDetector`'s `onTap`/`onDoubleTap`, because those two recognizers
/// share a gesture arena that would delay every single hold-to-talk press by
/// `kDoubleTapTimeout` while Flutter waits to see if a second tap follows —
/// unacceptable for a control FR-020 requires to attack within 50 ms of
/// grant. Manual pointer-timestamp comparison (mirroring the tuning knob's
/// own manual velocity tracking in `knob_widget.dart`) keeps every
/// hold-to-talk press instantaneous and layers latch-detection on top.
///
/// **PT/FR-021 gap, disclosed non-blocking (same class as the knob's
/// PT-vs-TS settle disclosure):** `keryx-face-prototype.html`'s own PTT
/// script implements only mousedown/touchstart/keydown → mouseup/touchend/
/// keyup hold-to-talk; latch mode is not present in the prototype at all, so
/// there is no PT-ratified double-tap timing window to match. This widget
/// uses Flutter's standard `kDoubleTapTimeout` (300 ms) as the most
/// defensible default absent a spec number, flagged for ORCH.
///
/// **PT/DS press-travel tension, disclosed non-blocking:** PT's own `.on`
/// (granted) rule uses `transform:translateY(2px)`, twice [KeryxTheme]'s
/// general `keyTravel` (1 dp) — but DS §4 states pressed-key travel is "the
/// same three changes on every control" (1 dp, lost top highlight, inner
/// shadow), explicitly generalized across every control. This widget follows
/// DS's explicit generalization (`KeryxTheme.keyTravel`) for consistency
/// with every other key-cap in the face, rather than PT's literal 2 px for
/// this one control — same resolution direction TASK-016 took for the
/// settle curve (DS's general rule over a PT-specific literal), flagged for
/// ORCH rather than silently picked.
class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    required this.state,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onLatchToggled,
    this.latchEnabled = false,
    this.enabled = true,
    this.height = 104,
    this.doubleTapWindow = kDoubleTapTimeout,
    this.onGrantHaptic,
    this.onDeniedHaptic,
  });

  /// Current PTT state — externally driven, see the library dartdoc.
  final PttState state;

  /// Fired on the leading edge of a hold-to-talk press (pointer-down),
  /// unless suppressed by a latch-toggle or latch-release gesture (see the
  /// class dartdoc's gesture contract).
  final VoidCallback onPressStart;

  /// Fired on the trailing edge of a hold-to-talk press (pointer-up or
  /// pointer-cancel), symmetrically suppressed with [onPressStart].
  final VoidCallback onPressEnd;

  /// Fired with `true` when a double-tap engages latch mode, `false` when a
  /// tap releases an already-latched floor (FR-021).
  final ValueChanged<bool> onLatchToggled;

  /// Setting gate for latch mode (FR-021: "as a setting"). When `false`,
  /// every press is a plain hold-to-talk gesture and [onLatchToggled] never
  /// fires.
  final bool latchEnabled;

  /// When `false`, all gestures are ignored (e.g. radio powered off).
  final bool enabled;

  /// TS §6.1 "≥ 96 dp tall" / PT `.ptt` `height:104px` — 104 is PT's own
  /// figure and clears the 96 dp floor with margin.
  final double height;

  /// Max gap between two pointer-downs to count as a latch-engaging
  /// double-tap. See the class dartdoc's PT/FR-021 gap disclosure.
  final Duration doubleTapWindow;

  /// Test/production seam for the grant haptic. Defaults to
  /// [PttHapticFeedback.grant].
  final Future<void> Function()? onGrantHaptic;

  /// Test/production seam for the denied haptic. Defaults to
  /// [PttHapticFeedback.denied].
  final Future<void> Function()? onDeniedHaptic;

  @override
  State<PttButton> createState() => PttButtonState();
}

/// Public so widget tests can inspect the deny-flash visual directly.
class PttButtonState extends State<PttButton> {
  /// PT `.deny` flash duration (L346: `setTimeout(..., 260)`).
  static const Duration denyFlashDuration = Duration(milliseconds: 260);

  DateTime? _lastPointerDownAt;
  bool _downWasSuppressed = false;
  bool _showDenyFlash = false;
  Timer? _denyFlashTimer;

  /// Exposed for widget tests: whether the transient deny-flash overlay is
  /// currently showing.
  @visibleForTesting
  bool get isShowingDenyFlash => _showDenyFlash;

  @override
  void didUpdateWidget(PttButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == PttState.denied &&
        oldWidget.state != PttState.denied) {
      unawaited((widget.onDeniedHaptic ?? PttHapticFeedback.denied)());
      _armDenyFlash();
    }
    if (widget.state == PttState.granted &&
        oldWidget.state != PttState.granted) {
      unawaited((widget.onGrantHaptic ?? PttHapticFeedback.grant)());
    }
  }

  void _armDenyFlash() {
    _denyFlashTimer?.cancel();
    setState(() => _showDenyFlash = true);
    _denyFlashTimer = Timer(denyFlashDuration, () {
      if (mounted) setState(() => _showDenyFlash = false);
    });
  }

  @override
  void dispose() {
    _denyFlashTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    final now = DateTime.now();

    if (widget.state == PttState.latched) {
      _downWasSuppressed = true;
      _lastPointerDownAt = now;
      widget.onLatchToggled(false);
      return;
    }

    final isDoubleTap =
        widget.latchEnabled &&
        _lastPointerDownAt != null &&
        now.difference(_lastPointerDownAt!) <= widget.doubleTapWindow;
    _lastPointerDownAt = now;

    if (isDoubleTap) {
      _downWasSuppressed = true;
      // Reset so a third rapid tap starts a fresh window rather than
      // re-triggering immediately.
      _lastPointerDownAt = null;
      widget.onLatchToggled(true);
      return;
    }

    _downWasSuppressed = false;
    widget.onPressStart();
  }

  void _onPointerUpOrCancel() {
    if (!widget.enabled) return;
    if (_downWasSuppressed) {
      _downWasSuppressed = false;
      return;
    }
    widget.onPressEnd();
  }

  _PttVisual _visualFor(PttState state) {
    switch (state) {
      case PttState.idle:
      case PttState.requesting:
        return const _PttVisual(
          // PT `.ptt` idle gradient (L114) — no theme token exists for this
          // exact key-cap gradient (only `KeryxTheme.shell500`/`shell700`
          // solids), same disclosed-hardcode class as TASK-012's glass-recess
          // chrome.
          gradientTop: Color(0xFF3A4045),
          gradientBottom: Color(0xFF272C30),
          foreground: Color(0xFFCFCBC0),
          pressed: false,
        );
      case PttState.granted:
      case PttState.latched:
        return const _PttVisual(
          // PT `.ptt.on` gradient (L118).
          gradientTop: Color(0xFF5A1D18),
          gradientBottom: Color(0xFF3A1310),
          foreground: Color(0xFFFFD9D4),
          pressed: true,
        );
      case PttState.denied:
        return const _PttVisual(
          // PT `.ptt.deny` gradient (L120).
          gradientTop: Color(0xFF3A2B18),
          gradientBottom: Color(0xFF2A1F12),
          foreground: Color(0xFFCFCBC0),
          pressed: false,
        );
    }
  }

  String _semanticValueFor(PttState state) {
    switch (state) {
      case PttState.idle:
        return 'idle';
      case PttState.requesting:
        return 'requesting';
      case PttState.granted:
        return 'transmitting';
      case PttState.denied:
        return 'denied';
      case PttState.latched:
        return 'transmitting, latched';
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _showDenyFlash
        ? _visualFor(PttState.denied)
        : _visualFor(widget.state);
    final pressed = visual.pressed;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Push to talk',
      value: _semanticValueFor(widget.state),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerUp: (_) => _onPointerUpOrCancel(),
        onPointerCancel: (_) => _onPointerUpOrCancel(),
        child: AnimatedContainer(
          key: const Key('keryx-ptt-surface'),
          duration: KeryxTheme.snapDuration,
          curve: KeryxTheme.snapCurve,
          width: double.infinity,
          height: widget.height,
          transform: pressed
              ? (Matrix4.identity()
                  ..translateByDouble(0.0, KeryxTheme.keyTravel, 0.0, 1.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[visual.gradientTop, visual.gradientBottom],
            ),
            boxShadow: pressed
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.5),
                      blurRadius: 6,
                      blurStyle: BlurStyle.inner,
                    ),
                  ]
                : KeryxTheme.raisedMaterialEdges,
          ),
          alignment: Alignment.center,
          child: Text('PTT', style: KeryxTheme.legendLabel.copyWith(
            color: visual.foreground,
            fontSize: 18,
          )),
        ),
      ),
    );
  }
}

@immutable
class _PttVisual {
  const _PttVisual({
    required this.gradientTop,
    required this.gradientBottom,
    required this.foreground,
    required this.pressed,
  });

  final Color gradientTop;
  final Color gradientBottom;
  final Color foreground;
  final bool pressed;
}
