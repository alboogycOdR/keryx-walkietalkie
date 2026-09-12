import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/onboarding/onboarding.dart';

List<String> _fixedWords() => RecoveryPhrase.generate(random: Random(1)).words;

Widget _app(Widget home, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: keryxUxThemeData(brightness: brightness),
    home: home,
  );
}

void main() {
  final words = _fixedWords();

  testWidgets('invalid callsign stays on the first step', (tester) async {
    String? done;
    await tester.pumpWidget(
      _app(
        OnboardingScreen(
          words: words,
          screenshotGuard: const NoopScreenshotGuard(),
          onDone: (c) => done = c,
        ),
      ),
    );
    await tester.enterText(find.byKey(OnboardingKeys.callsignField), 'x');
    await tester.tap(find.byKey(OnboardingKeys.continueButton));
    await tester.pump();
    expect(find.byKey(OnboardingKeys.callsignError), findsOneWidget);
    expect(find.byKey(OnboardingKeys.phraseScreen), findsNothing);
    expect(done, isNull);
  });

  testWidgets('confirmation is the only way to onDone', (tester) async {
    String? done;
    await tester.pumpWidget(
      _app(
        OnboardingScreen(
          words: words,
          screenshotGuard: const NoopScreenshotGuard(),
          onDone: (c) => done = c,
        ),
      ),
    );
    await tester.enterText(find.byKey(OnboardingKeys.callsignField), 'BRAVO-7');
    await tester.tap(find.byKey(OnboardingKeys.continueButton));
    await tester.pumpAndSettle();
    expect(find.byKey(OnboardingKeys.phraseScreen), findsOneWidget);
    expect(done, isNull);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byKey(OnboardingKeys.callsignScreen), findsOneWidget);
    expect(done, isNull);

    await tester.tap(find.byKey(OnboardingKeys.continueButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(OnboardingKeys.writtenDown));
    await tester.pump();
    expect(done, 'BRAVO-7');
  });

  testWidgets(
    'system back on the phrase step returns to callsign, not onDone',
    (tester) async {
      String? done;
      await tester.pumpWidget(
        _app(
          OnboardingScreen(
            words: words,
            screenshotGuard: const NoopScreenshotGuard(),
            onDone: (c) => done = c,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(OnboardingKeys.callsignField),
        'MIKE-9',
      );
      await tester.tap(find.byKey(OnboardingKeys.continueButton));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(OnboardingKeys.callsignScreen), findsOneWidget);
      expect(done, isNull);
    },
  );

  testWidgets('phrase grid is TalkBack-readable word by word', (tester) async {
    await tester.pumpWidget(
      _app(
        RecoveryPhraseScreen(
          words: words,
          screenshotGuard: const NoopScreenshotGuard(),
          onConfirmed: () {},
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      final finder = find.byKey(OnboardingKeys.phraseWord(i));
      expect(finder, findsOneWidget);
      final semantics = tester.getSemantics(finder);
      expect(semantics.label, OnboardingCopy.wordSemantics(i + 1, words[i]));
    }
  });

  testWidgets('phrase screen has no copy affordance', (tester) async {
    await tester.pumpWidget(
      _app(
        RecoveryPhraseScreen(
          words: words,
          screenshotGuard: const NoopScreenshotGuard(),
          onConfirmed: () {},
        ),
      ),
    );
    expect(find.byIcon(Icons.copy), findsNothing);
    expect(find.byIcon(Icons.copy_outlined), findsNothing);
    expect(find.byIcon(Icons.content_copy), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(SelectionArea), findsNothing);
    expect(find.byType(SelectionContainer), findsOneWidget);
  });

  testWidgets('phrase screen requests FLAG_SECURE for its lifetime', (
    tester,
  ) async {
    final guard = RecordingScreenshotGuard();
    await tester.pumpWidget(
      _app(
        RecoveryPhraseScreen(
          words: words,
          screenshotGuard: guard,
          onConfirmed: () {},
        ),
      ),
    );
    expect(guard.calls, <bool>[true]);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(guard.calls, <bool>[true, false]);
  });
}
