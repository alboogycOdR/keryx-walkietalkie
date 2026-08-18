import 'dart:math';

/// ICAO / NATO spelling alphabet. `JULIETT` and `XRAY` are the
/// standard forms (no hyphen inside the word).
const natoAlphabet = <String>[
  'ALPHA',
  'BRAVO',
  'CHARLIE',
  'DELTA',
  'ECHO',
  'FOXTROT',
  'GOLF',
  'HOTEL',
  'INDIA',
  'JULIETT',
  'KILO',
  'LIMA',
  'MIKE',
  'NOVEMBER',
  'OSCAR',
  'PAPA',
  'QUEBEC',
  'ROMEO',
  'SIERRA',
  'TANGO',
  'UNIFORM',
  'VICTOR',
  'WHISKEY',
  'XRAY',
  'YANKEE',
  'ZULU',
];

/// Display-only station name (FR-068 / TS §8.6). Never an election input.
class Callsign {
  static const minLength = 2;
  static const maxLength = 12;

  /// Same 2–12 class as the token-svc identity regex: letters, digits, hyphen.
  static final pattern = RegExp(r'^[A-Za-z0-9-]{2,12}$');

  /// Parses a user-edited callsign. Trims surrounding whitespace.
  ///
  /// Throws [FormatException] when the result is outside 2–12 chars or
  /// contains anything other than `A–Z`, `a–z`, `0–9`, or `-`.
  factory Callsign.parse(String raw) {
    final value = raw.trim();
    if (value.length < minLength || value.length > maxLength) {
      throw FormatException(
        'Callsign must be $minLength–$maxLength characters, got ${value.length}.',
      );
    }
    if (!pattern.hasMatch(value)) {
      throw const FormatException(
        'Callsign may contain only letters, digits, and hyphens.',
      );
    }
    return Callsign._(value);
  }

  const Callsign._(this.value);

  final String value;

  /// NATO word + 1–2 digit number, e.g. `BRAVO-7`, `SIERRA-19`.
  ///
  /// Number range is 1–99 inclusive (spec-silent; FR-068's examples
  /// are 7 and 19). Always uppercase, always in-range.
  factory Callsign.nato([Random? random]) {
    final rng = random ?? Random.secure();
    final word = natoAlphabet[rng.nextInt(natoAlphabet.length)];
    final number = rng.nextInt(99) + 1;
    return Callsign._('$word-$number');
  }

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is Callsign && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
