import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../core/presentation/telemetry.dart';

/// The floor-state treatment rendered by [TalkPttRing].
enum TalkPttRingTreatment {
  ready,
  requesting,
  tx,
  rx,
  latched,
  deniedFlash,
  neutral,
}

/// A standalone, state-coloured PTT surface for the Talk screen.
///
/// This widget deliberately has no radio/session dependency and reads no
/// theme. Its caller provides each colour and the authoritative floor state.
/// The actual Talk screen wires it in separately (ADR-002 A3/A4).
class TalkPttRing extends StatefulWidget {
  const TalkPttRing({
    super.key,
    required this.enabled,
    required this.treatment,
    required this.meterLevel,
    required this.reducedMotion,
    required this.semanticStatus,
    required this.ringColor,
    required this.faceColor,
    required this.glyphColor,
    required this.neutralRingColor,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.ringWidthFraction = .08,
    this.widthFraction = .78,
    this.maxDiameter = 300,
  });

  final bool enabled;
  final TalkPttRingTreatment treatment;
  final MeterLevel meterLevel;
  final bool reducedMotion;
  final String semanticStatus;
  final Color ringColor;
  final Color faceColor;
  final Color glyphColor;
  final Color neutralRingColor;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final double ringWidthFraction;
  final double widthFraction;
  final double maxDiameter;

  static const double minDiameter = 96;

  /// Calculates the responsive PTT diameter required by ADR-002 A3.
  static double sizeFor(
    double width, {
    double widthFraction = .78,
    double maxDiameter = 300,
  }) => (width * widthFraction).clamp(minDiameter, maxDiameter);

  /// Returns no shadow for decorative telemetry, preserving telemetry honesty.
  static List<BoxShadow> glowFor(MeterLevel meterLevel, Color ringColor) {
    if (meterLevel case MeasuredMeterLevel(:final value)) {
      final double normalized = value / 100;
      return <BoxShadow>[
        BoxShadow(
          color: ringColor.withValues(alpha: .12 + (.38 * normalized)),
          blurRadius: 6 + (20 * normalized),
          spreadRadius: 1 + (4 * normalized),
        ),
      ];
    }
    return const <BoxShadow>[];
  }

  @override
  State<TalkPttRing> createState() => _TalkPttRingState();
}

class _TalkPttRingState extends State<TalkPttRing>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _sweepController;
  late final AnimationController _shakeController;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _syncTreatmentAnimations();
  }

  @override
  void didUpdateWidget(covariant TalkPttRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.treatment != widget.treatment ||
        oldWidget.reducedMotion != widget.reducedMotion) {
      _syncTreatmentAnimations();
    }
  }

  void _syncTreatmentAnimations() {
    final bool animate = !widget.reducedMotion;
    if (animate && widget.treatment == TalkPttRingTreatment.requesting) {
      _sweepController.repeat();
    } else {
      _sweepController.stop();
      _sweepController.value = 0;
    }
    if (animate && widget.treatment == TalkPttRingTreatment.deniedFlash) {
      _shakeController.forward(from: 0);
    } else {
      _shakeController.stop();
      _shakeController.value = 0;
    }
  }

  void _beginHold() {
    if (!widget.enabled || _holding) return;
    setState(() => _holding = true);
    _pressController.forward();
    HapticFeedback.lightImpact();
    widget.onHoldStart();
  }

  void _endHold() {
    if (!_holding) return;
    setState(() => _holding = false);
    _pressController.reverse();
    widget.onHoldEnd();
  }

  void _toggleHold() {
    if (_holding) {
      _endHold();
    } else {
      _beginHold();
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _sweepController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Color get _effectiveRingColor => switch (widget.treatment) {
    TalkPttRingTreatment.deniedFlash ||
    TalkPttRingTreatment.neutral => widget.neutralRingColor,
    _ => widget.ringColor,
  };

  Color _pressedFace(double value) => Color.from(
    alpha: widget.faceColor.a,
    red: widget.faceColor.r * (1 - (.15 * value)),
    green: widget.faceColor.g * (1 - (.15 * value)),
    blue: widget.faceColor.b * (1 - (.15 * value)),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double diameter = TalkPttRing.sizeFor(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : widget.maxDiameter,
          widthFraction: widget.widthFraction,
          maxDiameter: widget.maxDiameter,
        );
        final Color ringColor = _effectiveRingColor;
        final Map<CustomSemanticsAction, VoidCallback> actions =
            <CustomSemanticsAction, VoidCallback>{
              CustomSemanticsAction(
                label: _holding ? 'Stop transmitting' : 'Start transmitting',
              ): _toggleHold,
            };

        return Semantics(
          key: const Key('keryx-talk-ptt-disc-semantics'),
          button: true,
          enabled: widget.enabled,
          label: 'Push to talk',
          value: widget.semanticStatus,
          customSemanticsActions: actions,
          child: Focus(
            onKeyEvent: (FocusNode node, KeyEvent event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                _toggleHold();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SizedBox(
              key: const Key('keryx-talk-ptt-disc'),
              width: diameter,
              height: diameter,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _beginHold(),
                onPointerUp: (_) => _endHold(),
                onPointerCancel: (_) => _endHold(),
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[
                    _pressController,
                    _sweepController,
                    _shakeController,
                  ]),
                  builder: (BuildContext context, Widget? child) {
                    final double shake = widget.reducedMotion
                        ? 0
                        : math.sin(_shakeController.value * math.pi * 3) * 8;
                    return Transform.translate(
                      offset: Offset(shake, 0),
                      child: Transform.scale(
                        scale: 1 - (.03 * _pressController.value),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: TalkPttRing.glowFor(
                              widget.meterLevel,
                              ringColor,
                            ),
                          ),
                          child: CustomPaint(
                            painter: TalkPttRingPainter(
                              treatment: widget.treatment,
                              ringColor: widget.enabled
                                  ? ringColor
                                  : ringColor.withValues(alpha: .35),
                              faceColor: _pressedFace(_pressController.value),
                              glyphColor: widget.glyphColor,
                              ringWidthFraction: widget.ringWidthFraction,
                              sweepProgress: widget.reducedMotion
                                  ? 0
                                  : _sweepController.value,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the parameter-driven face, state ring, and state glyph.
///
/// This is public so the ring's state-colour contract remains directly
/// inspectable in widget tests without relying on pixels or a golden fixture.
class TalkPttRingPainter extends CustomPainter {
  const TalkPttRingPainter({
    required this.treatment,
    required this.ringColor,
    required this.faceColor,
    required this.glyphColor,
    required this.ringWidthFraction,
    required this.sweepProgress,
  });

  final TalkPttRingTreatment treatment;
  final Color ringColor;
  final Color faceColor;
  final Color glyphColor;
  final double ringWidthFraction;
  final double sweepProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final double diameter = math.min(size.width, size.height);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double stroke = diameter * ringWidthFraction;
    final Rect ringBounds = Rect.fromCircle(
      center: center,
      radius: (diameter - stroke) / 2,
    );
    canvas.drawCircle(
      center,
      (diameter - stroke) / 2,
      Paint()..color = faceColor,
    );
    final Paint ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, (diameter - stroke) / 2, ringPaint);
    if (treatment == TalkPttRingTreatment.requesting) {
      final Paint sweepPaint = Paint()
        ..color = glyphColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        ringBounds,
        (sweepProgress * math.pi * 2) - (math.pi / 4),
        math.pi / 2,
        false,
        sweepPaint,
      );
    }
    final IconData glyph = switch (treatment) {
      TalkPttRingTreatment.rx => Icons.volume_up,
      TalkPttRingTreatment.neutral => Icons.mic_off,
      _ => Icons.mic,
    };
    final TextPainter iconPainter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: TextStyle(
          fontFamily: glyph.fontFamily,
          package: glyph.fontPackage,
          color: glyphColor,
          fontSize: diameter * .26,
        ),
      ),
    )..layout();
    iconPainter.paint(
      canvas,
      center - Offset(iconPainter.width / 2, iconPainter.height / 2),
    );
    if (treatment == TalkPttRingTreatment.latched) {
      final double badgeRadius = diameter * .11;
      final Offset badgeCenter = Offset(
        center.dx + (diameter * .27),
        center.dy + (diameter * .27),
      );
      canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = faceColor);
      final TextPainter badgePainter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: String.fromCharCode(Icons.lock.codePoint),
          style: TextStyle(
            fontFamily: Icons.lock.fontFamily,
            color: glyphColor,
            fontSize: badgeRadius * 1.4,
          ),
        ),
      )..layout();
      badgePainter.paint(
        canvas,
        badgeCenter - Offset(badgePainter.width / 2, badgePainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TalkPttRingPainter oldDelegate) =>
      treatment != oldDelegate.treatment ||
      ringColor != oldDelegate.ringColor ||
      faceColor != oldDelegate.faceColor ||
      glyphColor != oldDelegate.glyphColor ||
      ringWidthFraction != oldDelegate.ringWidthFraction ||
      sweepProgress != oldDelegate.sweepProgress;
}
