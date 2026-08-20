import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:keryx/core/theme/theme.dart';

/// The moulded housing shell behind the whole face: `shell-700` base, a
/// single top-left light source, and a 2-3% monochrome noise overlay
/// (DS §4 "Housing = `--shell-700` with a 2-3% monochrome noise overlay
/// (moulded texture)"), using the token TASK-028 added specifically for
/// this (`KeryxTheme.housingNoiseOverlayOpacity`).
class KeryxHousing extends StatelessWidget {
  const KeryxHousing({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: KeryxTheme.shell700,
        gradient: RadialGradient(
          center: const Alignment(-0.7, -0.85),
          radius: 1.3,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.05),
            Colors.transparent,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child,
          IgnorePointer(
            child: CustomPaint(
              painter: _NoiseOverlayPainter(
                opacity: KeryxTheme.housingNoiseOverlayOpacity,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deterministic monochrome speckle field — no image asset, no per-frame
/// cost (painted once per layout size; the RepaintBoundary above the housing
/// keeps it off the hot animation path).
class _NoiseOverlayPainter extends CustomPainter {
  const _NoiseOverlayPainter({required this.opacity});

  final double opacity;
  static const int _dotCount = 900;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || size.width <= 0 || size.height <= 0) return;
    final random = math.Random(7);
    final paint = Paint();
    for (var i = 0; i < _dotCount; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final lightness = random.nextBool() ? Colors.white : Colors.black;
      paint.color = lightness.withValues(
        alpha: opacity * (0.4 + random.nextDouble() * 0.6),
      );
      canvas.drawRect(Rect.fromLTWH(dx, dy, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _NoiseOverlayPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
