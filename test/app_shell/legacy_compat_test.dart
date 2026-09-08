import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TASK-048 acceptance criterion: "The legacy face remains reachable only
/// through a development-only route that is not present in a normal user
/// navigation path" (Technical §10).
///
/// `lib/app.dart`'s default-wired `FaceScreen()` performs real platform I/O
/// on `initState` (secure storage, real session/audio/service factories —
/// see `FaceScreen`'s own dartdoc and `test/features/face/face_screen_test
/// .dart`'s `FakeSessionHost`/`_identityFactory` comments for why every
/// other test in this repo injects fakes rather than mounting the
/// default-wired widget). There is no injection seam at `app.dart`'s call
/// site to fake that out for a runtime widget test without either widening
/// `FaceScreen`'s already-frozen public API (outside this task's
/// `Owned_Paths`) or constructing a second, parallel host — both of which
/// TASK-048 deliberately avoids. `test/app_shell/mobile_app_shell_test
/// .dart` already proves the legacy route is unreachable *from* the shell
/// (no widget links to it); this file instead verifies the registration
/// itself is gated and singular, by reading `lib/app.dart`'s own source —
/// a legitimate provenance check for a purely structural criterion.
void main() {
  test('legacyFaceRouteName is registered exactly once, gated behind '
      'kDebugMode, in lib/app.dart', () {
    final source = File('lib/app.dart').readAsStringSync();

    final registrations = RegExp(r'legacyFaceRouteName\s*:').allMatches(source);
    expect(
      registrations.length,
      1,
      reason: 'exactly one registration site — never duplicated, never '
          'wired into a second route table',
    );

    final registrationLine = source
        .split('\n')
        .firstWhere((line) => line.contains('legacyFaceRouteName:'));
    expect(
      registrationLine.trim().startsWith('if (kDebugMode)'),
      isTrue,
      reason: 'must be gated behind kDebugMode so it never ships in a '
          'release build',
    );

    // Not present in a normal user navigation path: no destination widget
    // (NavigationDestination/ListTile/TextButton/IconButton) in the shell
    // sources under test references it by name.
    for (final path in <String>[
      'lib/app_shell/mobile_app_shell.dart',
      'lib/app_shell/channels_screen.dart',
      'lib/app_shell/talk_screen.dart',
      'lib/app_shell/shell_routes.dart',
      'lib/app_shell/shell_keys.dart',
    ]) {
      final shellSource = File(path).readAsStringSync();
      expect(
        shellSource.contains('legacyFaceRouteName'),
        isFalse,
        reason: '$path must never link to the dev-only legacy route',
      );
    }
  });
}
