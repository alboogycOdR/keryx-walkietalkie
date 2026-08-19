import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/knob/knob_feedback.dart';
import 'package:keryx/features/knob/knob_physics.dart';

/// Per-detent feedback hook, fired once per channel crossed. `delta` is the
/// signed channel change this call represents — almost always `±1` for a
/// direct drag, but may batch a larger magnitude when
/// [KnobPhysics.maxTicksPerSecond] withheld intermediate fling ticks (see
/// [KnobFlywheel]). Never fired with `delta == 0`.
///
/// The caller wires audio (8 ms tick sample) and the LCD update from this
/// same call — [KeryxTuningKnob] itself only owns the haptic half of TS
/// §6.2's "all in the same frame" contract (see [KnobHapticFeedback]).
typedef KnobDetentCallback = void Function(int delta);

/// The hero rotary tuning knob (TS D1, §6.2, §6.4; DS §5.1).
///
/// Pure presentation + intent — this widget owns no tuning state. [channel]
/// is the host's current absolute channel (from TASK-004/027's
/// `RadioReducer`), consumed only to clamp deltas at the 1/99 boundary
/// (ORCH ruling 2026-08-19T18:30:00Z, follow-up k: CLAMP, not wrap — see
/// `knob_physics.dart`'s library dartdoc). The reducer's `TuneTo` event
/// carries absolute channel/code; this widget deliberately does not depend
/// on a `tuneDelta` reducer event (none exists yet) — it resolves deltas
/// locally and leaves dispatching `TuneTo(channel: current + delta, ...)`
/// to the caller.
class KeryxTuningKnob extends StatefulWidget {
  const KeryxTuningKnob({
    super.key,
    required this.channel,
    required this.onDetent,
    this.size = 96,
    this.enabled = true,
    this.onHapticClick,
  });

  /// Current absolute channel (1-99). Used only to clamp fling/drag deltas
  /// at the boundary; this widget does not own or mutate it.
  final int channel;

  /// Fired once per resolved detent crossing. See the typedef dartdoc for
  /// the same-frame contract.
  final KnobDetentCallback onDetent;

  /// DS §5.1: "Knurled, 96 dp".
  final double size;

  /// When `false`, drags/flings are ignored (e.g. radio powered off).
  final bool enabled;

  /// Test/production seam for the per-detent haptic. Defaults to
  /// [KnobHapticFeedback.click] — override only in tests, to avoid
  /// depending on a real platform vibrator channel.
  final Future<void> Function()? onHapticClick;

  @override
  State<KeryxTuningKnob> createState() => KeryxTuningKnobState();
}

/// Public so widget tests can drive/inspect knob state directly.
class KeryxTuningKnobState extends State<KeryxTuningKnob>
    with SingleTickerProviderStateMixin {
  double _angle = 0; // degrees, unbounded — matches PT's `knobAngle`.
  double? _lastPointerAngle;
  double _lastMoveVelocity = 0; // deg/frame, PT-normalized (`d/dt*16`).
  DateTime? _lastMoveTime;
  int _virtualChannel = 0;
  bool _dragging = false;

  KnobFlywheel? _flywheel;
  late final Ticker _ticker;
  Duration _lastTickElapsed = Duration.zero;

  /// Current continuous knob angle in degrees — exposed for widget tests.
  @visibleForTesting
  double get angle => _angle;

  /// `true` while the flywheel is still decaying after a fling.
  @visibleForTesting
  bool get isFlinging => _flywheel != null;

  @override
  void initState() {
    super.initState();
    _virtualChannel = widget.channel;
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(KeryxTuningKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && _flywheel == null) {
      _virtualChannel = widget.channel;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double _angleFrom(Offset local, Offset center) {
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    return math.atan2(dy, dx) * 180 / math.pi;
  }

  void _onPanStart(DragStartDetails details, Offset center) {
    if (!widget.enabled) return;
    _flywheel = null;
    _ticker.stop();
    _dragging = true;
    _virtualChannel = widget.channel;
    _lastPointerAngle = _angleFrom(details.localPosition, center);
    _lastMoveVelocity = 0;
    _lastMoveTime = DateTime.now();
  }

  void _onPanUpdate(DragUpdateDetails details, Offset center) {
    if (!widget.enabled || !_dragging) return;
    final now = DateTime.now();
    final a = _angleFrom(details.localPosition, center);
    var d = a - (_lastPointerAngle ?? a);
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    final dtMs = _lastMoveTime == null
        ? 16.0
        : math.max(1, now.difference(_lastMoveTime!).inMilliseconds)
              .toDouble();
    _lastMoveVelocity = d / dtMs * 16;
    _lastPointerAngle = a;
    _lastMoveTime = now;
    _applyAngleDelta(d);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    _dragging = false;
    final fling = KnobFlywheel(
      initialVelocity: _lastMoveVelocity,
      startAngle: _angle,
    );
    if (fling.isFinished) return;
    _flywheel = fling;
    _lastTickElapsed = Duration.zero;
    _ticker.start();
  }

  void _onPanCancel() {
    _dragging = false;
  }

  void _applyAngleDelta(double deltaDegrees) {
    final beforeIndex = KnobPhysics.detentIndexFor(_angle);
    _angle += deltaDegrees;
    final afterIndex = KnobPhysics.detentIndexFor(_angle);
    final raw = afterIndex - beforeIndex;
    if (raw != 0) _emit(raw);
    setState(() {});
  }

  void _onTick(Duration elapsed) {
    final fw = _flywheel;
    if (fw == null) return;
    final elapsedMs = _lastTickElapsed == Duration.zero
        ? 16.0
        : (elapsed - _lastTickElapsed).inMicroseconds / 1000.0;
    _lastTickElapsed = elapsed;
    final delta = fw.step(elapsedMs <= 0 ? 16 : elapsedMs);
    _angle = fw.angle;
    if (delta != 0) _emit(delta);
    if (fw.isFinished) {
      _ticker.stop();
      _flywheel = null;
    }
    if (mounted) setState(() {});
  }

  void _emit(int rawDelta) {
    final clamped = KnobPhysics.clampDelta(_virtualChannel, rawDelta);
    if (clamped == 0) return;
    _virtualChannel += clamped;
    unawaited((widget.onHapticClick ?? KnobHapticFeedback.click)());
    widget.onDetent(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final center = Offset(widget.size / 2, widget.size / 2);
    return Semantics(
      slider: true,
      label: 'Tuning knob',
      value: 'Channel ${widget.channel}',
      child: GestureDetector(
        // Semantics for this widget come solely from the explicit
        // `Semantics` wrapper above (slider + channel value). Without this,
        // GestureDetector auto-maps its onPan* handlers onto
        // scrollLeft/Right/Up/Down semantic actions, which would advertise
        // scroll-gesture accessibility support this widget does not
        // implement (its accessible tuning path is TASK-014's steppers,
        // FR-106) and would be misleading to a screen reader.
        excludeFromSemantics: true,
        // `.down`, not the default `.start`: with `.start`, the recognizer
        // waits for the pointer to clear the pan slop tolerance before
        // firing `onPanStart`, then reports that *later* (slop-cleared)
        // position as the start point while silently folding the
        // slop-distance itself into the first `onPanUpdate`'s delta — a
        // real touch-drag jump the user genuinely made, but one this arc
        // angle math must not double-count relative to the true down
        // point. `.down` reports the actual pointer-down position as the
        // start, so every subsequent delta is a literal, unadjusted
        // difference — required for `detentIndexFor` to stay exact.
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (details) => _onPanStart(details, center),
        onPanUpdate: (details) => _onPanUpdate(details, center),
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanCancel,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: RepaintBoundary(
            child: CustomPaint(
              key: const Key('keryx-knob-paint'),
              painter: _KnobPainter(
                angle: _angle,
                olive: KeryxTheme.olive,
                shell: KeryxTheme.shell500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Knurled knob body + olive indicator line (DS §5.1).
class _KnobPainter extends CustomPainter {
  const _KnobPainter({
    required this.angle,
    required this.olive,
    required this.shell,
  });

  final double angle;
  final Color olive;
  final Color shell;

  static const int _knurlCount = 36;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(center, radius, Paint()..color = shell);

    final knurlPaint = Paint()
      ..color = const Color.fromRGBO(0, 0, 0, 0.35)
      ..strokeWidth = 1;
    for (var i = 0; i < _knurlCount; i++) {
      final theta = (2 * math.pi * i) / _knurlCount;
      final direction = Offset(math.cos(theta), math.sin(theta));
      canvas.drawLine(
        center + direction * (radius * 0.85),
        center + direction * radius,
        knurlPaint,
      );
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle * math.pi / 180);
    canvas.drawLine(
      Offset(radius * 0.35, 0),
      Offset(radius * 0.85, 0),
      Paint()
        ..color = olive
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) =>
      oldDelegate.angle != angle ||
      oldDelegate.olive != olive ||
      oldDelegate.shell != shell;
}
