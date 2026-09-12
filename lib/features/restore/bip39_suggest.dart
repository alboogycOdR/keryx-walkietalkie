import 'package:keryx/core/identity/bip39_wordlist.dart';

/// Prefix suggestions from the pinned BIP-39 English list.
List<String> suggestBip39(String prefix, {int limit = 6}) {
  final p = prefix.trim().toLowerCase();
  if (p.isEmpty) return const <String>[];
  final out = <String>[];
  for (final word in bip39EnglishWordlist) {
    if (word.startsWith(p)) {
      out.add(word);
      if (out.length >= limit) break;
    }
  }
  return out;
}

bool isBip39Word(String word) {
  final w = word.trim().toLowerCase();
  if (w.isEmpty) return false;
  return bip39EnglishWordlist.contains(w);
}
