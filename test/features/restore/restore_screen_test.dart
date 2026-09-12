import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/restore/restore.dart';

Widget _app(Widget home) {
  return MaterialApp(theme: keryxUxThemeData(), home: home);
}

Future<void> _enterWords(WidgetTester tester, List<String> words) async {
  for (var i = 0; i < words.length; i++) {
    final finder = find.byKey(RestoreKeys.word(i));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.enterText(finder, words[i]);
  }
  await tester.pump();
}

void main() {
  testWidgets('rejects an invalid word inline and keeps Restore disabled', (
    tester,
  ) async {
    await tester.pumpWidget(_app(RestoreScreen(onRestored: (_) {})));
    await tester.enterText(find.byKey(RestoreKeys.word(0)), 'notaword');
    await tester.pump();
    expect(find.byKey(RestoreKeys.wordError(0)), findsOneWidget);
    expect(find.text(RestoreCopy.invalidWord), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(RestoreKeys.submit));
    expect(button.onPressed, isNull);
  });

  testWidgets('suggestions appear for a BIP-39 prefix', (tester) async {
    await tester.pumpWidget(_app(RestoreScreen(onRestored: (_) {})));
    await tester.tap(find.byKey(RestoreKeys.word(0)));
    await tester.enterText(find.byKey(RestoreKeys.word(0)), 'aba');
    await tester.pump();
    expect(find.byKey(RestoreKeys.suggestion('abandon')), findsOneWidget);
    await tester.tap(find.byKey(RestoreKeys.suggestion('abandon')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(RestoreKeys.word(0)))
          .controller!
          .text,
      'abandon',
    );
  });

  testWidgets('valid phrase reproduces the original ID', (tester) async {
    final phrase = RecoveryPhrase.generate(random: Random(42));
    final original = await phrase.deriveKeyPair();
    final originalPeerId = derivePeerId(original.publicKey);
    final originalCode = deriveShortCode(original.publicKey);

    DeviceIdentity? restored;
    await tester.pumpWidget(
      _app(RestoreScreen(onRestored: (id) => restored = id)),
    );
    await _enterWords(tester, phrase.words);
    for (var i = 0; i < phrase.words.length; i++) {
      expect(
        tester.widget<TextField>(find.byKey(RestoreKeys.word(i))).controller!.text,
        phrase.words[i],
      );
    }
    expect(
      tester.widget<FilledButton>(find.byKey(RestoreKeys.submit)).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(RestoreKeys.submit));
    await tester.pumpAndSettle();

    expect(restored, isNotNull);
    expect(restored!.peerId, originalPeerId);
    expect(restored!.shortCode, originalCode);
    expect(restored!.keyPair!.publicKey, original.publicKey);
    expect(restored!.keyPair!.seed, original.seed);
  });

  testWidgets('checksum mismatch shows an error and does not restore', (
    tester,
  ) async {
    final phrase = RecoveryPhrase.generate(random: Random(7));
    final shuffled = List<String>.of(phrase.words)..[0] = phrase.words[1];
    shuffled[1] = phrase.words[0];
    expect(
      () => RecoveryPhrase.parse(shuffled.join(' ')),
      throwsA(isA<InvalidRecoveryPhraseException>()),
    );

    DeviceIdentity? restored;
    await tester.pumpWidget(
      _app(RestoreScreen(onRestored: (id) => restored = id)),
    );
    await _enterWords(tester, shuffled);
    await tester.tap(find.byKey(RestoreKeys.submit));
    await tester.pumpAndSettle();
    expect(restored, isNull);
    expect(find.byKey(RestoreKeys.checksumError), findsOneWidget);
  });
}
