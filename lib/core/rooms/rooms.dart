/// Channel → roomId derivation (KRX-053 / TS §8.7).
///
/// Pure Dart. Numbered and keyed formulas; the token service and
/// Event QR consume the 16-character room hash, never a passphrase.
library;

export 'derivation.dart';
export 'rfc4648_base32.dart';
