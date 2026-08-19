import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';

void main() {
  setUp(() {
    // Every test starts from the default plate — a prior test's swap must
    // never leak into the next one.
    KeryxTheme.facePlate.value = KeryxFacePlate.fieldBlack;
  });

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

  group('TASK-028 — glass-recess chrome (PT `.glass` L51-58)', () {
    test('matches the values TASK-012 had to hardcode', () {
      expect(KeryxTheme.glassBorder, const Color(0xFF0A0F0C));
      expect(
        KeryxTheme.glassInnerShadow.color,
        const Color.fromRGBO(0, 0, 0, 0.85),
      );
      expect(KeryxTheme.glassInnerShadow.offset, const Offset(0, 3));
      expect(KeryxTheme.glassInnerShadow.blurRadius, 10);
      expect(KeryxTheme.glassInnerShadow.blurStyle, BlurStyle.inner);
      expect(
        KeryxTheme.glassHighlight.color,
        const Color.fromRGBO(255, 255, 255, 0.05),
      );
      expect(KeryxTheme.glassBloomStop, Colors.transparent);
    });
  });

  group('TASK-028 — new material/geometry constants', () {
    test('key travel is 1 dp per DS §4 / TS §6.4', () {
      expect(KeryxTheme.keyTravel, 1);
    });

    test('housing noise overlay is within DS §4\'s stated 2-3% range', () {
      expect(KeryxTheme.housingNoiseOverlayOpacity, greaterThanOrEqualTo(0.02));
      expect(KeryxTheme.housingNoiseOverlayOpacity, lessThanOrEqualTo(0.03));
    });

    test('max gradient height fraction is 20% per DS §4', () {
      expect(KeryxTheme.maxGradientHeightFraction, 0.20);
    });

    test('panelBodyStrong carries a real Inter 600 wght axis, not synthesised bold', () {
      expect(KeryxTheme.panelBodyStrong.fontFamily, 'Inter');
      expect(KeryxTheme.panelBodyStrong.fontWeight, FontWeight.w600);
      expect(
        KeryxTheme.panelBodyStrong.fontVariations,
        contains(const FontVariation('wght', 600)),
      );
    });
  });

  group('TASK-028 — faceplate seam (DS §8 / FR-101)', () {
    test('default plate is the free "Field Black"', () {
      expect(KeryxTheme.facePlate.value.name, 'Field Black');
      expect(KeryxTheme.facePlate.value, KeryxFacePlate.fieldBlack);
    });

    test('swapping the active plate changes every colour projection at runtime', () {
      const KeryxFacePlate probe = KeryxFacePlate(
        name: 'Probe',
        shell900: Color(0xFF000001),
        shell700: Color(0xFF000002),
        shell500: Color(0xFF000003),
        glass: Color(0xFF000004),
        lcd: Color(0xFF000005),
        legend: Color(0xFF000006),
        tx: Color(0xFF000007),
        rx: Color(0xFF000008),
        emergency: Color(0xFF000009),
        olive: Color(0xFF00000A),
        glassBorder: Color(0xFF00000B),
        glassInnerShadowColor: Color.fromRGBO(1, 2, 3, 0.4),
        glassHighlightColor: Color.fromRGBO(5, 6, 7, 0.8),
      );

      KeryxTheme.facePlate.value = probe;

      expect(KeryxTheme.shell900, probe.shell900);
      expect(KeryxTheme.shell700, probe.shell700);
      expect(KeryxTheme.shell500, probe.shell500);
      expect(KeryxTheme.glass, probe.glass);
      expect(KeryxTheme.lcd, probe.lcd);
      expect(KeryxTheme.legend, probe.legend);
      expect(KeryxTheme.tx, probe.tx);
      expect(KeryxTheme.rx, probe.rx);
      expect(KeryxTheme.emergency, probe.emergency);
      expect(KeryxTheme.olive, probe.olive);
      expect(KeryxTheme.glassBorder, probe.glassBorder);
      expect(KeryxTheme.glassInnerShadow.color, probe.glassInnerShadowColor);
      expect(KeryxTheme.glassHighlight.color, probe.glassHighlightColor);

      // Layout is untouched by a faceplate swap — DS §8's hard boundary.
      expect(KeryxTheme.faceAllocation.grille, 0.26);
      expect(KeryxTheme.keyTravel, 1);
    });

    test('notifies listeners on swap, so widgets can react live', () {
      var notified = 0;
      void listener() => notified++;
      KeryxTheme.facePlate.addListener(listener);
      addTearDown(() => KeryxTheme.facePlate.removeListener(listener));

      KeryxTheme.facePlate.value = const KeryxFacePlate(
        name: 'Probe',
        shell900: Color(0xFF000001),
        shell700: Color(0xFF000002),
        shell500: Color(0xFF000003),
        glass: Color(0xFF000004),
        lcd: Color(0xFF000005),
        legend: Color(0xFF000006),
        tx: Color(0xFF000007),
        rx: Color(0xFF000008),
        emergency: Color(0xFF000009),
        olive: Color(0xFF00000A),
        glassBorder: Color(0xFF00000B),
        glassInnerShadowColor: Color.fromRGBO(1, 2, 3, 0.4),
        glassHighlightColor: Color.fromRGBO(5, 6, 7, 0.8),
      );

      expect(notified, 1);
    });
  });
}
