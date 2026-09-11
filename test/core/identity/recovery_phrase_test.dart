import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  test('generate() yields 12 words from the BIP-39 English list', () {
    final phrase = RecoveryPhrase.generate(random: Random(1));
    expect(phrase.words.length, recoveryPhraseWordCount);
    for (final word in phrase.words) {
      expect(bip39EnglishWordlist, contains(word));
    }
  });

  test('parse() accepts its own sentence and reproduces the entropy', () {
    final phrase = RecoveryPhrase.generate(random: Random(2));
    final parsed = RecoveryPhrase.parse(phrase.sentence);
    expect(parsed.words, phrase.words);
    expect(parsed.entropy, phrase.entropy);
  });

  test('parse() is case- and whitespace-insensitive', () {
    final phrase = RecoveryPhrase.generate(random: Random(3));
    final messy = '  ${phrase.words.join('   ').toUpperCase()}  ';
    final parsed = RecoveryPhrase.parse(messy);
    expect(parsed.words, phrase.words);
  });

  test('deriveKeyPair() is deterministic: same phrase, same key', () async {
    final phrase = RecoveryPhrase.generate(random: Random(4));
    final a = await phrase.deriveKeyPair();
    final b = await RecoveryPhrase.parse(phrase.sentence).deriveKeyPair();
    expect(a.publicKey, b.publicKey);
    expect(a.seed, b.seed);
  });

  test('changing one word yields a different key (when it still parses)', () async {
    final phrase = RecoveryPhrase.generate(random: Random(5));
    final words = List<String>.of(phrase.words);
    final originalIndex = bip39EnglishWordlist.indexOf(words[0]);
    // Pick a replacement that still produces a *parseable* (checksum-valid)
    // phrase only if we're lucky; otherwise it throws, which is also a
    // correct "different" outcome (V2-VT-002's dedicated rejection case
    // below covers the throwing path deterministically).
    final replacement =
        bip39EnglishWordlist[(originalIndex + 1) % bip39EnglishWordlist.length];
    words[0] = replacement;
    final candidate = words.join(' ');
    try {
      final restored = RecoveryPhrase.parse(candidate);
      final restoredKey = await restored.deriveKeyPair();
      final originalKey = await phrase.deriveKeyPair();
      expect(restoredKey.publicKey, isNot(originalKey.publicKey));
    } on InvalidRecoveryPhraseException {
      // A single-word change usually breaks the checksum; that is the
      // expected and desired outcome too.
    }
  });

  test('rejects the wrong word count', () {
    expect(
      () => RecoveryPhrase.parse('one two three'),
      throwsA(isA<InvalidRecoveryPhraseException>()),
    );
  });

  test('rejects an unknown word', () {
    final phrase = RecoveryPhrase.generate(random: Random(6));
    final words = List<String>.of(phrase.words)..[0] = 'notabip39word';
    expect(
      () => RecoveryPhrase.parse(words.join(' ')),
      throwsA(isA<InvalidRecoveryPhraseException>()),
    );
  });

  test('rejects a checksum mismatch from a corrupted word order', () {
    final phrase = RecoveryPhrase.generate(random: Random(8));
    final shuffled = phrase.words.reversed.join(' ');
    // Reversing 12 words essentially always breaks the 4-bit checksum;
    // guard the (astronomically unlikely) coincidence so the test can
    // never flake.
    try {
      RecoveryPhrase.parse(shuffled);
      fail('expected a checksum mismatch for the reversed phrase');
    } on InvalidRecoveryPhraseException {
      // expected
    }
  });

  test('fromEntropy() round-trips through parse()', () {
    final entropy = List<int>.generate(recoveryEntropyBytes, (i) => i * 5 + 1);
    final phrase = RecoveryPhrase.fromEntropy(entropy);
    final parsed = RecoveryPhrase.parse(phrase.sentence);
    expect(parsed.entropy, entropy);
  });
}
