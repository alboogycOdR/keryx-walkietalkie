import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';

void main() {
  test('closed squelch is silent', () {
    final g = BedMixer.gainsFor(0);
    expect(g.bed1, 0);
    expect(g.bed2, 0);
    expect(g.bed3, 0);
  });

  test('one-third is bed1 only', () {
    final g = BedMixer.gainsFor(1 / 3);
    expect(g.bed1, closeTo(1, 1e-9));
    expect(g.bed2, 0);
    expect(g.bed3, 0);
  });

  test('two-thirds is bed2 only', () {
    final g = BedMixer.gainsFor(2 / 3);
    expect(g.bed1, closeTo(0, 1e-9));
    expect(g.bed2, closeTo(1, 1e-9));
    expect(g.bed3, 0);
  });

  test('open squelch is bed3 only', () {
    final g = BedMixer.gainsFor(1);
    expect(g.bed1, closeTo(0, 1e-12));
    expect(g.bed2, closeTo(0, 1e-12));
    expect(g.bed3, closeTo(1, 1e-12));
  });

  test('mid first third crossfades silence into bed1', () {
    final g = BedMixer.gainsFor(1 / 6);
    expect(g.bed1, closeTo(0.5, 1e-9));
    expect(g.bed2, 0);
    expect(g.bed3, 0);
  });

  test('rejects out of range', () {
    expect(() => BedMixer.gainsFor(-0.01), throwsArgumentError);
    expect(() => BedMixer.gainsFor(1.01), throwsArgumentError);
    expect(() => BedMixer.gainsFor(double.nan), throwsArgumentError);
  });
}
