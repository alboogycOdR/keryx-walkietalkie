import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/ptt/ptt_haptics.dart';
import 'package:keryx/features/ptt/ptt_state.dart';

/// Injectable amplitude source for [PttButton]'s 64-tick meter ring.
///
/// Values are percentages in `0..100`. The default preview controller moves
/// gently so the component remains useful in isolation; production callers
/// inject their live mic/RX value.
class PttRingController extends ValueNotifier<double> {
  PttRingController([double level = 0]) : super(level.clamp(0, 100).toDouble());

  factory PttRingController.preview() => _PreviewPttRingController();

  void setLevel(double level) => value = level.clamp(0, 100).toDouble();

  @visibleForTesting
  static int litTickCountForLevel(double level) =>
      ((level.clamp(0, 100) / 100) * _PttRingPainter.tickCount).round();
}

class _PreviewPttRingController extends PttRingController {
  _PreviewPttRingController() : super(24) {
    _ticker = Timer.periodic(const Duration(milliseconds: 110), (_) {
      _phase += .16;
      setLevel(18 + ((math.sin(_phase) + 1) * 22));
    });
  }

  late final Timer _ticker;
  double _phase = 0;

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }
}

/// The Phase 2 hero push-to-talk disc.
///
/// It preserves the existing floor-intent callbacks and haptic seam. Callers
/// own [PttState] and inject a meter [ringController]; this widget samples no
/// audio and reads no session state.
class PttButton extends StatefulWidget {
  const PttButton({
    super.key,
    required this.state,
    required this.onPressStart,
    required this.onPressEnd,
    required this.onLatchToggled,
    this.ringController,
    this.latchEnabled = false,
    this.enabled = true,
    this.outerDiameter = 320,
    this.faceDiameter = 236,
    this.doubleTapWindow = kDoubleTapTimeout,
    this.onGrantHaptic,
    this.onDeniedHaptic,
  });

  final PttState state;
  final VoidCallback onPressStart;
  final VoidCallback onPressEnd;
  final ValueChanged<bool> onLatchToggled;
  final ValueListenable<double>? ringController;
  final bool latchEnabled;
  final bool enabled;
  final double outerDiameter;
  final double faceDiameter;
  final Duration doubleTapWindow;
  final Future<void> Function()? onGrantHaptic;
  final Future<void> Function()? onDeniedHaptic;

  @override
  State<PttButton> createState() => PttButtonState();
}

class PttButtonState extends State<PttButton> {
  DateTime? _lastPointerDownAt;
  bool _downWasSuppressed = false;
  bool _pointerDown = false;
  PttRingController? _previewController;

  @visibleForTesting
  bool get isPressed => _pointerDown || _isTransmitState(widget.state);

  ValueListenable<double> get _ringController =>
      widget.ringController ??
      (_previewController ??= PttRingController.preview());

  @override
  void didUpdateWidget(PttButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isTransmitState(widget.state) && !_isTransmitState(oldWidget.state)) {
      unawaited((widget.onGrantHaptic ?? PttHapticFeedback.grant)());
    }
    if (widget.state == PttState.denied && oldWidget.state != PttState.denied) {
      unawaited((widget.onDeniedHaptic ?? PttHapticFeedback.denied)());
    }
  }

  @override
  void dispose() {
    _previewController?.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    setState(() => _pointerDown = true);
    final now = DateTime.now();
    if (widget.state == PttState.latched) {
      _downWasSuppressed = true;
      _lastPointerDownAt = now;
      widget.onLatchToggled(false);
      return;
    }
    final doubleTap =
        widget.latchEnabled &&
        _lastPointerDownAt != null &&
        now.difference(_lastPointerDownAt!) <= widget.doubleTapWindow;
    _lastPointerDownAt = now;
    if (doubleTap) {
      _downWasSuppressed = true;
      _lastPointerDownAt = null;
      widget.onLatchToggled(true);
      return;
    }
    _downWasSuppressed = false;
    widget.onPressStart();
  }

  void _onPointerUpOrCancel() {
    if (!widget.enabled) return;
    setState(() => _pointerDown = false);
    if (_downWasSuppressed) {
      _downWasSuppressed = false;
      return;
    }
    widget.onPressEnd();
  }

  static bool _isTransmitState(PttState state) =>
      state == PttState.granted || state == PttState.latched;

  _DiscVisual _visualFor(PttState state) {
    if (state == PttState.receiving) {
      return _DiscVisual(KeryxTheme.rx, 'BUSY', Icons.volume_up_outlined);
    }
    if (state == PttState.emergency) {
      return _DiscVisual(
        KeryxTheme.emergency,
        'CANCEL',
        Icons.mic_none_outlined,
      );
    }
    if (_isTransmitState(state)) {
      return _DiscVisual(KeryxTheme.tx, 'PTT', Icons.mic_none_outlined);
    }
    return _DiscVisual(KeryxTheme.lcd, 'PTT', Icons.mic_none_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(widget.state);
    final pressed = isPressed;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Push to talk',
      value: visual.legend.toLowerCase(),
      child: SizedBox(
        key: const Key('keryx-ptt-disc'),
        width: widget.outerDiameter,
        height: widget.outerDiameter,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerUp: (_) => _onPointerUpOrCancel(),
          onPointerCancel: (_) => _onPointerUpOrCancel(),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ValueListenableBuilder<double>(
                valueListenable: _ringController,
                builder: (context, level, _) => Semantics(
                  label:
                      'Amplitude meter, ${PttRingController.litTickCountForLevel(level)} of 64 ticks',
                  child: CustomPaint(
                    key: const Key('keryx-ptt-ring'),
                    size: Size.square(widget.outerDiameter),
                    painter: _PttRingPainter(
                      level: level,
                      activeColor: visual.color,
                      inactiveColor: visual.color.withValues(alpha: .14),
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                key: const Key('keryx-ptt-surface'),
                duration: KeryxTheme.snapDuration,
                curve: KeryxTheme.snapCurve,
                width: widget.faceDiameter,
                height: widget.faceDiameter,
                transform: pressed
                    ? (Matrix4.identity()
                        ..translateByDouble(0, KeryxTheme.keyTravel, 0, 1))
                    : Matrix4.identity(),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color.lerp(KeryxTheme.shell500, visual.color, .22)!,
                      Color.lerp(KeryxTheme.shell900, visual.color, .12)!,
                    ],
                  ),
                  border: Border.all(color: visual.color.withValues(alpha: .7)),
                  boxShadow: pressed
                      ? const <BoxShadow>[
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, .55),
                            blurRadius: 8,
                            blurStyle: BlurStyle.inner,
                          ),
                        ]
                      : KeryxTheme.raisedMaterialEdges,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      visual.icon,
                      key: const Key('keryx-ptt-glyph'),
                      color: visual.color,
                      size: 54,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      visual.legend,
                      key: const Key('keryx-ptt-legend'),
                      style: KeryxTheme.legendLabel.copyWith(
                        color: visual.color,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

@immutable
class _DiscVisual {
  const _DiscVisual(this.color, this.legend, this.icon);
  final Color color;
  final String legend;
  final IconData icon;
}

class _PttRingPainter extends CustomPainter {
  const _PttRingPainter({
    required this.level,
    required this.activeColor,
    required this.inactiveColor,
  });
  final double level;
  final Color activeColor;
  final Color inactiveColor;
  static const int tickCount = 64;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;
    final litPerSide = PttRingController.litTickCountForLevel(level) ~/ 2;
    final paint = Paint()
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < tickCount; index++) {
      final distanceFromTop = index <= tickCount ~/ 2
          ? index
          : tickCount - index;
      final lit = distanceFromTop <= litPerSide;
      final angle = -math.pi / 2 + ((2 * math.pi * index) / tickCount);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final inner =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 11);
      paint.color = lit ? activeColor : inactiveColor;
      canvas.drawLine(inner, outer, paint);
    }
  }

  @override
  bool shouldRepaint(_PttRingPainter old) =>
      old.level != level ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
