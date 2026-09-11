import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  test('has exactly 2048 unique, sorted, lowercase words', () {
    expect(bip39EnglishWordlist.length, 2048);
    expect(bip39EnglishWordlist.toSet().length, 2048);
    final sorted = List<String>.of(bip39EnglishWordlist)..sort();
    expect(bip39EnglishWordlist, sorted);
    for (final word in bip39EnglishWordlist) {
      expect(word, word.toLowerCase());
      expect(word, isNotEmpty);
    }
  });

  test('contains known canonical BIP-39 English words at index 0 and 2047', () {
    expect(bip39EnglishWordlist.first, 'abandon');
    expect(bip39EnglishWordlist.last, 'zoo');
  });
}
