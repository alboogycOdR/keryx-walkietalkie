import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';

void main() {
  group('KeryxTheme colours', () {
    test('matches the ratified housing, glass, and signal tokens', () {
      expect(KeryxTheme.shell900, const Color(0xFF15181B));
      expect(KeryxTheme.shell700, const Color(0xFF22262A));
      expect(KeryxTheme.shell500, const Color(0xFF31363B));
      expect(KeryxTheme.glass, const Color(0xFF0F1512));
      expect(KeryxTheme.lcd, const Color(0xFFF2A93B));
      expect(KeryxTheme.legend, const Color(0xFFCFCBC0));
      expect(KeryxTheme.tx, const Color(0xFFE23D2E));
      expect(KeryxTheme.rx, const Color(0xFF7FD1A0));
      expect(KeryxTheme.emergency, const Color(0xFFFF7A18));
      expect(KeryxTheme.olive, const Color(0xFF6B7052));
      expect(KeryxTheme.ghostSegmentOpacity, 0.07);
    });
  });

  test('provides the locked type scale and grid', () {
    expect(KeryxTheme.grid, 8);
    expect(KeryxTheme.channelNumerals.fontFamily, 'DSEG7 Classic');
    expect(KeryxTheme.channelNumerals.fontSize, 56);
    expect(KeryxTheme.channelNumerals.height, 1);
    expect(KeryxTheme.glassSecondary.fontFamily, 'Share Tech Mono');
    expect(KeryxTheme.glassSecondary.fontSize, 15);
    expect(KeryxTheme.glassSecondary.height, 1.2);
    expect(KeryxTheme.telltale.fontSize, 11);
    expect(KeryxTheme.telltale.height, 1);
    expect(KeryxTheme.legendLabel.letterSpacing, 1.54);
    expect(KeryxTheme.panelBody.fontFamily, 'Inter');
    expect(KeryxTheme.panelBody.height, 1.5);
  });

  test('exposes only the prototype motion timings and face allocation', () {
    expect(KeryxTheme.snapDuration, const Duration(milliseconds: 140));
    expect(KeryxTheme.settleDuration, const Duration(milliseconds: 320));
    expect(KeryxTheme.snapCurve, const Cubic(0.2, 0.9, 0.3, 1));
    expect(KeryxTheme.settleCurve, const Cubic(0.16, 1, 0.3, 1));
    expect(KeryxTheme.faceAllocation.total, closeTo(1, 0.000001));
    expect(KeryxTheme.faceAllocation.grille, 0.26);
    expect(KeryxTheme.raisedMaterialEdges, hasLength(2));
  });
}
