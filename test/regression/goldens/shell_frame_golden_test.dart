import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';

import '../regression_shell_harness.dart';

/// TASK-078 — Verification §6 / ADR-002 A1: golden of the R2 shell frame
/// (top app bar + icon tab strip + Talk body), dark and light. Isolated
/// Talk-state goldens in `talk_states_golden_test.dart` do not include the
/// chrome; this file is the composition that the owner reviews.
void main() {
  for (final Brightness brightness in <Brightness>[
    Brightness.dark,
    Brightness.light,
  ]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('R2 shell frame — Talk tab with app bar + tab strip ($suffix)', (
      tester,
    ) async {
      await pumpRegressionShell(
        tester,
        size: const Size(1080, 1920),
        brightness: brightness,
      );

      await expectLater(
        find.byType(MobileAppShell),
        matchesGoldenFile('goldens/shell_frame_$suffix.png'),
      );
    });
  }
}
