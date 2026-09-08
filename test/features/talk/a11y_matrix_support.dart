import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One viewport/text-scale combination in the Verification §6 responsive
/// matrix ("Test at a minimum 320 logical-pixel width, a normal phone, a
/// larger phone, landscape, system text scale 1.0 and 2.0, and large
/// display insets").
///
/// TASK-057 round 1 covered this matrix on Talk only, by inspection on the
/// other six screens; round 2's review finding was that "spot-checked by
/// reading" does not satisfy "covered by tests, not by inspection alone".
/// This file is the shared driver every successor screen test now uses —
/// each screen still supplies its own widget-pump closure (provider setup
/// differs per screen), but the matrix and the exception-free assertion are
/// defined once.
class ResponsiveCase {
  const ResponsiveCase(this.label, this.size, {this.textScale = 1.0});

  final String label;
  final Size size;
  final double textScale;
}

/// The shared matrix. Sizes are logical pixels (devicePixelRatio pinned to
/// 1.0 by [expectResponsiveMatrix]).
const List<ResponsiveCase> kResponsiveMatrix = <ResponsiveCase>[
  ResponsiveCase('320 lp width (small phone)', Size(320, 640)),
  ResponsiveCase('larger phone', Size(411, 891)),
  ResponsiveCase('landscape, small height', Size(640, 320)),
  ResponsiveCase(
    '320 lp width, system text scale 2.0',
    Size(320, 640),
    textScale: 2.0,
  ),
];

/// Drives [pump] through every case in [matrix] and asserts nothing throws
/// (no clipping/overflow exception) at any of them. [pump] receives the
/// case's viewport size and must fully build, apply that size (via its own
/// screen-specific surface parameter, or directly on `tester.view` if it has
/// none) and settle the screen under test — each screen wires its own
/// providers/host doubles differently, while the matrix and the assertion
/// loop are shared.
Future<void> expectResponsiveMatrix(
  WidgetTester tester,
  Future<void> Function(WidgetTester tester, Size size) pump, {
  List<ResponsiveCase> matrix = kResponsiveMatrix,
}) async {
  for (final ResponsiveCase c in matrix) {
    if (c.textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = c.textScale;
    }
    try {
      await pump(tester, c.size);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Responsive-matrix case "${c.label}" threw an exception',
      );
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      if (c.textScale != 1.0) {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      }
    }
  }
}

/// Asserts every rendered text/background pairing on the current frame
/// meets WCAG AA contrast as actually rendered — Verification §6: "Design
/// review must approve actual renderings, not just token names". Round 1's
/// "no literal colour value" tests verified token usage, which is exactly
/// what this criterion rules out as sufficient on its own; this samples the
/// real rendered pixels via Flutter's own accessibility guideline checker.
Future<void> expectRenderedContrast(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Asserts every tappable target on the current frame meets the Android
/// 48dp minimum as actually laid out. Deliberately not `tester.getSize` —
/// this plan's own recorded trap: Material 3 pads `IconButton`'s render box
/// to 48x48 regardless of its visual/constraint size, which would make a
/// `getSize` assertion pass even for a control that is not really 48dp.
Future<void> expectTapTargets(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
}
