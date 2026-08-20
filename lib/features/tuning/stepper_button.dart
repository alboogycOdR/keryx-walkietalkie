import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

import 'tuning_haptics.dart';
import 'tuning_physics.dart';

/// CH▲ / CH▼ direction.
enum StepDirection { up, down }

/// Fired for every emitted step, `delta` already clamped to the domain
/// (`±1`, or `0`-suppressed at a boundary — see [ChStepperButton] dartdoc).
/// Pure intent: this widget owns no channel state.
typedef ChannelStepCallback = void Function(int delta);

/// CH▲/CH▼ stepper button (FR-004, D1, FR-106) — the accessible, precision
/// tuning path flanking the knob.
///
/// **Auto-repeat.** Mirrors PT `stepper()` exactly
/// (`specs/keryx-face-prototype.html` L327-336, "the ratified feel" per the
/// task dossier): the first step fires synchronously on press, then after
/// [TuningPhysics.initialRepeatDelay] (420 ms) the button starts repeating,
/// accelerating by [TuningPhysics.repeatAcceleration] (×0.82) every
/// subsequent tick down to a floor of [TuningPhysics.minRepeatRateMs]
/// (60 ms). Every tick emits one PRIMITIVE_CLICK haptic
/// ([TuningHapticFeedback.click]) synchronously with [onStep] — same
/// same-frame contract [KeryxTuningKnob] documents for its own detents
/// (TS §6.2), so the knob and the steppers feel identical.
///
/// **Domain clamp, not wrap.** [channel] is the widget's read-only view of
/// the *current* device channel (owned by the caller's reducer projection,
/// TASK-004/027); every tick clamps against
/// [TuningPhysics.minimumChannel]/[TuningPhysics.maximumChannel] via
/// [TuningPhysics.clampChannelDelta] and simply stops emitting once a
/// boundary tick would be a no-op — CLAMP semantics per the 2026-08-19
/// ORCH ruling (follow-up k), identical to `KeryxTuningKnob`'s.
///
/// **CH▼'s long-press quick-recall (FR-009) — disclosed overlap with
/// auto-repeat.** PT never implements channel memory at all (grep-confirmed
/// absent from the prototype), so there is no ratified reference for how
/// "press-and-hold auto-repeat" (FR-004) and "long-press for quick-recall"
/// (FR-009) should coexist on the *same* CH▼ gesture. This widget resolves
/// it as: the immediate first tick and any auto-repeat ticks that land
/// before [TuningPhysics.recallLongPressThreshold] (600 ms — reused from the
/// established `EmgKey` long-press convention for cross-widget consistency)
/// fire normally; once the threshold is crossed, auto-repeat is cancelled
/// and [onLongPress] fires instead, so the press does not continue
/// stepping down while the recall surface is open. A hold that crosses
/// 600 ms therefore emits one or two extra step-down ticks (at 0 ms and
/// 420 ms) before recall opens — a minor, non-blocking UX overlap, disclosed
/// here rather than silently resolved, same class as TASK-013/015's PT-gap
/// precedents. [onLongPress] is only meaningful when supplied (CH▼); CH▲
/// passes `null`.
class ChStepperButton extends StatefulWidget {
  const ChStepperButton({
    super.key,
    required this.direction,
    required this.channel,
    required this.onStep,
    this.onLongPress,
    this.enabled = true,
    this.width = 54,
    this.height = 54,
    this.semanticsLabel,
  });

  /// Which direction this instance steps.
  final StepDirection direction;

  /// The current device channel — read-only input, not owned by this widget.
  final int channel;

  /// Fired once per emitted, already-clamped step. Never fired with
  /// `delta == 0`.
  final ChannelStepCallback onStep;

  /// Fired once when a hold crosses [TuningPhysics.recallLongPressThreshold]
  /// (CH▼'s quick-recall gesture, FR-009). See the class dartdoc's
  /// "disclosed overlap" section. `null` disables the long-press gesture
  /// entirely (CH▲ has none).
  final VoidCallback? onLongPress;

  /// When `false`, the button is inert (e.g. radio powered off).
  final bool enabled;

  /// PT `.step` `width:54px` (L86) — already clears the FR-106 48 dp floor.
  final double width;

  /// PT `.step` `height:54px` (L86).
  final double height;

  /// Overrides the default TalkBack label ("Channel up" / "Channel down").
  final String? semanticsLabel;

  @override
  State<ChStepperButton> createState() => ChStepperButtonState();
}

/// Public so widget tests can drive/inspect timers directly.
class ChStepperButtonState extends State<ChStepperButton> {
  int _virtualChannel = 0;
  bool _pressed = false;
  double _rate = TuningPhysics.initialRepeatRateMs;
  Timer? _repeatTimer;
  Timer? _longPressTimer;

  /// Exposed for widget tests: whether the long-press quick-recall gesture
  /// has already fired for the current press.
  @visibleForTesting
  bool longPressFired = false;

  int get _dirValue => widget.direction == StepDirection.up ? 1 : -1;

  @override
  void initState() {
    super.initState();
    _virtualChannel = widget.channel;
  }

  @override
  void didUpdateWidget(covariant ChStepperButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.channel != oldWidget.channel) {
      _virtualChannel = widget.channel;
    }
  }

  void _tick() {
    final delta = TuningPhysics.clampChannelDelta(_virtualChannel, _dirValue);
    if (delta == 0) return;
    _virtualChannel += delta;
    unawaited(TuningHapticFeedback.click());
    widget.onStep(delta);
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    setState(() => _pressed = true);
    longPressFired = false;
    _tick();
    _rate = TuningPhysics.initialRepeatRateMs;
    _repeatTimer?.cancel();
    _repeatTimer = Timer(TuningPhysics.initialRepeatDelay, _repeat);
    if (widget.onLongPress != null) {
      _longPressTimer?.cancel();
      _longPressTimer = Timer(TuningPhysics.recallLongPressThreshold, () {
        if (!mounted) return;
        longPressFired = true;
        _repeatTimer?.cancel();
        widget.onLongPress!();
      });
    }
  }

  void _repeat() {
    if (!mounted) return;
    _tick();
    _rate = (_rate * TuningPhysics.repeatAcceleration).clamp(
      TuningPhysics.minRepeatRateMs,
      TuningPhysics.initialRepeatRateMs,
    );
    _repeatTimer = Timer(Duration(milliseconds: _rate.round()), _repeat);
  }

  void _onUpOrCancel() {
    if (!widget.enabled) return;
    _repeatTimer?.cancel();
    _longPressTimer?.cancel();
    setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUp = widget.direction == StepDirection.up;
    final glyph = isUp ? '▲' : '▼';
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel ?? (isUp ? 'Channel up' : 'Channel down'),
      // The glyph/legend below are purely decorative echoes of the label
      // already stated here — without this, their child Text nodes would
      // merge into the announced semantics ("Channel up\nCH\n▲").
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerUp: (_) => _onUpOrCancel(),
        onPointerCancel: (_) => _onUpOrCancel(),
        child: AnimatedContainer(
          key: ValueKey<String>(
            'keryx-stepper-${isUp ? 'up' : 'down'}',
          ),
          duration: KeryxTheme.snapDuration,
          curve: KeryxTheme.snapCurve,
          width: widget.width,
          height: widget.height,
          transform: _pressed
              ? (Matrix4.identity()
                  ..translateByDouble(0.0, KeryxTheme.keyTravel, 0.0, 1.0))
              : Matrix4.identity(),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: KeryxTheme.shell500,
            borderRadius: BorderRadius.circular(12),
            boxShadow: _pressed
                ? const <BoxShadow>[
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.6),
                      blurRadius: 6,
                      blurStyle: BlurStyle.inner,
                    ),
                  ]
                : KeryxTheme.raisedMaterialEdges,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'CH',
                // PT `.step` (L86-89): Barlow Condensed 13px, letter-spacing
                // .1em, NO font-weight declared (i.e. normal/400) — a
                // deliberate departure from `KeryxTheme.legendLabel`'s
                // general silk-screen-legend rule (11px/600/.14em, DS §3),
                // because this literal PT class is specific to the stepper
                // glyph, not the general legend rule. Disclosed, non-blocking,
                // same class as prior PT-vs-DS numeric-drift precedents.
                style: KeryxTheme.legendLabel.copyWith(
                  color: KeryxTheme.legend,
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  letterSpacing: 13 * 0.1,
                ),
              ),
              Text(
                glyph,
                style: KeryxTheme.legendLabel.copyWith(
                  color: KeryxTheme.legend,
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
