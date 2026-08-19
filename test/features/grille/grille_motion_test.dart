import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/grille/grille_motion.dart';

void main() {
  test('clamps finite amplitude into [0, 1] and rejects non-finite', () {
    expect(GrilleMotion.clampAmplitude(-0.4), 0);
    expect(GrilleMotion.clampAmplitude(0.4), 0.4);
    expect(GrilleMotion.clampAmplitude(2), 1);
    expect(GrilleMotion.clampAmplitude(double.nan), 0);
    expect(GrilleMotion.clampAmplitude(double.infinity), 0);
  });

  test('rest scale is 1 at zero amplitude regardless of phase', () {
    expect(
      GrilleMotion.scaleY(
        amplitude: 0,
        barIndex: 3,
        elapsedMs: 440,
        jitter: 1.2,
      ),
      1,
    );
  });

  test('tremble matches the prototype phase-offset formula', () {
    const amp = 0.8;
    const i = 2;
    const t = 270.0;
    const jitter = 0.9;
    expect(
      GrilleMotion.scaleY(
        amplitude: amp,
        barIndex: i,
        elapsedMs: t,
        jitter: jitter,
      ),
      1 + math.sin(t / 90 + i) * 0.5 * amp * jitter,
    );
  });

  test('MONITOR convention is the prototype 0.25 amplitude', () {
    expect(GrilleMotion.monitorAmplitude, 0.25);
    expect(GrilleMotion.barCount, 9);
  });

  test('jitter samples the prototype 0.6 .. 1.2 band', () {
    final random = math.Random(7);
    for (var i = 0; i < 40; i++) {
      final jitter = GrilleMotion.sampleJitter(random);
      expect(jitter, inInclusiveRange(0.6, 1.2));
    }
  });

  test('settle tokens consumed by the grille are the ratified DS §10 values', () {
    expect(KeryxTheme.settleDuration, const Duration(milliseconds: 320));
    final curve = KeryxTheme.settleCurve;
    expect(curve, isA<Cubic>());
    final cubic = curve as Cubic;
    expect(cubic.a, 0.16);
    expect(cubic.b, 1);
    expect(cubic.c, 0.3);
    expect(cubic.d, 1);
  });
}
