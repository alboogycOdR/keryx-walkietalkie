/// 12-word BIP-39 recovery phrase for a KERYX identity (Technical §3.2,
/// V2-FR-002/003).
///
/// `entropy` (128 bits) encodes/decodes to 12 English BIP-39 words with the
/// standard checksum. The seed fed to the Ed25519 key derivation is *not*
/// the standard BIP-39 PBKDF2 mnemonic-to-seed function — Technical §3.2
/// specifies HKDF-SHA256(entropy, info: `keryx-id-v1`) directly, which this
/// module implements as [RecoveryPhrase.deriveKeyPair].
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart' show Hkdf, Hmac, SecretKey;

import 'bip39_wordlist.dart';
import 'keys.dart';

/// Entropy size in bytes for a 12-word phrase (128 bits, Technical §3.2).
const recoveryEntropyBytes = 16;

/// Number of words in a KERYX recovery phrase.
const recoveryPhraseWordCount = 12;

const _hkdfInfo = 'keryx-id-v1';

/// Thrown when a phrase fails to parse: wrong word count, a word outside
/// the BIP-39 English list, or a checksum mismatch (V2-VT-002).
class InvalidRecoveryPhraseException implements Exception {
  const InvalidRecoveryPhraseException(this.message);
  final String message;

  @override
  String toString() => 'InvalidRecoveryPhraseException: $message';
}

/// A validated 12-word BIP-39 recovery phrase and the 128-bit entropy it
/// encodes.
class RecoveryPhrase {
  const RecoveryPhrase._(this.words, this.entropy);

  /// The 12 lowercase English words, in order.
  final List<String> words;

  /// The 128-bit entropy the words encode (before the checksum bits).
  final Uint8List entropy;

  /// Generates a fresh phrase from a cryptographically secure RNG.
  factory RecoveryPhrase.generate({Random? random}) {
    final rng = random ?? Random.secure();
    final entropy = Uint8List.fromList(
      List<int>.generate(recoveryEntropyBytes, (_) => rng.nextInt(256)),
    );
    return RecoveryPhrase.fromEntropy(entropy);
  }

  /// Builds a phrase from raw 128-bit [entropy] (mainly for tests /
  /// frozen vectors).
  factory RecoveryPhrase.fromEntropy(List<int> entropy) {
    if (entropy.length != recoveryEntropyBytes) {
      throw ArgumentError.value(
        entropy.length,
        'entropy.length',
        'must be $recoveryEntropyBytes bytes',
      );
    }
    final checksumBit = sha256.convert(entropy).bytes[0] >> 4; // top 4 bits
    final bits = StringBuffer();
    for (final byte in entropy) {
      bits.write(byte.toRadixString(2).padLeft(8, '0'));
    }
    bits.write(checksumBit.toRadixString(2).padLeft(4, '0'));
    final bitString = bits.toString();

    final words = <String>[];
    for (var i = 0; i < recoveryPhraseWordCount; i++) {
      final slice = bitString.substring(i * 11, i * 11 + 11);
      words.add(bip39EnglishWordlist[int.parse(slice, radix: 2)]);
    }
    return RecoveryPhrase._(
      List.unmodifiable(words),
      Uint8List.fromList(entropy),
    );
  }

  /// Parses and validates a phrase a user typed or scanned. Rejects the
  /// wrong word count, an unknown word, or a bad checksum (a single
  /// changed word almost always fails the checksum — V2-VT-002).
  factory RecoveryPhrase.parse(String phrase) {
    final words = phrase
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length != recoveryPhraseWordCount) {
      throw InvalidRecoveryPhraseException(
        'expected $recoveryPhraseWordCount words, got ${words.length}',
      );
    }
    final indexOf = <String, int>{
      for (var i = 0; i < bip39EnglishWordlist.length; i++)
        bip39EnglishWordlist[i]: i,
    };
    final bits = StringBuffer();
    for (final word in words) {
      final index = indexOf[word];
      if (index == null) {
        throw InvalidRecoveryPhraseException('"$word" is not a BIP-39 word');
      }
      bits.write(index.toRadixString(2).padLeft(11, '0'));
    }
    final bitString = bits.toString();
    final entropyBits = bitString.substring(0, recoveryEntropyBytes * 8);
    final checksumBits = bitString.substring(recoveryEntropyBytes * 8);

    final entropy = Uint8List(recoveryEntropyBytes);
    for (var i = 0; i < recoveryEntropyBytes; i++) {
      entropy[i] = int.parse(
        entropyBits.substring(i * 8, i * 8 + 8),
        radix: 2,
      );
    }
    final expectedChecksum = sha256.convert(entropy).bytes[0] >> 4;
    final actualChecksum = int.parse(checksumBits, radix: 2);
    if (expectedChecksum != actualChecksum) {
      throw const InvalidRecoveryPhraseException('checksum mismatch');
    }
    return RecoveryPhrase._(List.unmodifiable(words), entropy);
  }

  /// The phrase as a single space-separated string, e.g. for display.
  String get sentence => words.join(' ');

  /// Derives the Ed25519 identity key pair for this phrase: HKDF-SHA256
  /// over [entropy] with info `keryx-id-v1` (Technical §3.2) yields the
  /// 32-byte Ed25519 seed. The same phrase always yields the same key;
  /// restoring from the words reproduces the same peerId (V2-FR-003).
  Future<IdentityKeyPair> deriveKeyPair() async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: identityKeyLength);
    final seedKey = await hkdf.deriveKey(
      secretKey: SecretKey(entropy),
      info: utf8.encode(_hkdfInfo),
    );
    final seedBytes = await seedKey.extractBytes();
    return IdentityKeyPair.fromSeed(seedBytes);
  }
}
