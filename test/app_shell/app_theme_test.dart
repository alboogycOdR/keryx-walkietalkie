import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TASK-048 Review round 1 finding (1): `lib/app.dart` must wire
/// TASK-047's `keryxUxThemeData()` as `MaterialApp.theme` — the "final
/// wiring" site named in Technical §9 — instead of the placeholder
/// `ThemeData.dark(useMaterial3: true)` it originally shipped with.
///
/// This is a source-provenance check, the same pattern
/// `legacy_compat_test.dart` uses and documents: `lib/app.dart`'s
/// `_KeryxMaterialShell` is not exported (private to that library file), so
/// no test file can reference it directly, and `KeryxApp` itself cannot be
/// pumped in a widget test because its internal `ProviderScope` has no
/// override seam and its default providers boot real platform I/O (secure
/// storage, audio, radio service) that no widget test in this repo runs
/// unmocked. `mobile_app_shell_test.dart`'s "KeryxUxTokens resolves
/// non-null under the shell's real theme wiring" case covers the runtime
/// half — that `keryxUxThemeData()`'s own output really does resolve a
/// non-null `KeryxUxTokens` extension for downstream widgets — using the
/// exact same theme value this test proves is the one actually wired.
void main() {
  test(
    'lib/app.dart wires keryxUxThemeData() as MaterialApp.theme, not a '
    'literal ThemeData',
    () {
      final String source = File('lib/app.dart').readAsStringSync();

      expect(
        source.contains('import \'package:keryx/core/theme/ux_tokens.dart\''),
        isTrue,
        reason: 'must import TASK-047\'s theme factory',
      );

      final String themeLine = source
          .split('\n')
          .firstWhere((line) => line.trim().startsWith('theme:'));
      expect(
        themeLine.trim(),
        'theme: keryxUxThemeData(),',
        reason:
            'MaterialApp.theme must be TASK-047\'s successor tokens (Design '
            '§3.1: dark is the default), not the pre-redesign literal '
            'ThemeData.dark(...) placeholder',
      );

      expect(
        source.contains('ThemeData.dark('),
        isFalse,
        reason: 'the placeholder literal theme must be fully replaced, not '
            'left alongside the real one',
      );
    },
  );
}
