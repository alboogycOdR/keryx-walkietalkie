import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/onboarding/onboarding.dart';

void main() {
  final words = RecoveryPhrase.generate(random: Random(1)).words;

  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: KeyedSubtree(
          key: const Key('phrase-golden-root'),
          child: RecoveryPhraseScreen(
            words: words,
            screenshotGuard: const NoopScreenshotGuard(),
            onConfirmed: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('phrase-golden-root')),
      matchesGoldenFile('goldens/phrase_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('phrase screen golden ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: suffix, brightness: brightness);
    });
  }
}
