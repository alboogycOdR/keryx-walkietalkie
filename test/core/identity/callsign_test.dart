import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

void main() {
  test('NATO generator matches FR-068 examples in shape', () {
    final rng = Random(1);
    for (var i = 0; i < 80; i++) {
      final cs = Callsign.nato(rng);
      expect(cs.value.length, inInclusiveRange(Callsign.minLength, Callsign.maxLength));
      expect(Callsign.pattern.hasMatch(cs.value), isTrue);
      final parts = cs.value.split('-');
      expect(parts, hasLength(2));
      expect(natoAlphabet, contains(parts[0]));
      final n = int.parse(parts[1]);
      expect(n, inInclusiveRange(1, 99));
    }
  });

  test('NATO generator is deterministic under a seeded Random', () {
    expect(Callsign.nato(Random(99)).value, Callsign.nato(Random(99)).value);
  });

  test('every NATO word produces a legal 2–12 callsign at 1 and 99', () {
    for (final word in natoAlphabet) {
      expect(() => Callsign.parse('$word-1'), returnsNormally);
      expect(() => Callsign.parse('$word-99'), returnsNormally);
    }
    expect(natoAlphabet, hasLength(26));
    expect(natoAlphabet, containsAll(['BRAVO', 'SIERRA', 'JULIETT', 'XRAY']));
  });

  test('parse accepts the spec examples and the token-svc charset', () {
    expect(Callsign.parse('BRAVO-7').value, 'BRAVO-7');
    expect(Callsign.parse('SIERRA-19').value, 'SIERRA-19');
    expect(Callsign.parse('  ab  ').value, 'ab');
    expect(Callsign.parse('A1').value, 'A1');
    expect(Callsign.parse('abcdefghijkl').value, 'abcdefghijkl');
  });

  test('parse rejects length and charset edges', () {
    expect(() => Callsign.parse(''), throwsFormatException);
    expect(() => Callsign.parse('A'), throwsFormatException);
    expect(() => Callsign.parse('abcdefghijklm'), throwsFormatException);
    expect(() => Callsign.parse('BRAVO 7'), throwsFormatException);
    expect(() => Callsign.parse('BRAVO_7'), throwsFormatException);
    expect(() => Callsign.parse('你好'), throwsFormatException);
  });

  test('no uniqueness check on parse — collisions are a display concern', () {
    final a = Callsign.parse('BRAVO-7');
    final b = Callsign.parse('BRAVO-7');
    expect(a, b);
  });
}
