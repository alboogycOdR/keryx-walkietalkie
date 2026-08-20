import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/ptt/ptt_haptics.dart';

void main() {
  group('PttHapticFeedback', () {
    test('denied pattern is pulse/pause/pulse matching PT [18,40,18]', () {
      expect(PttHapticFeedback.deniedPattern, <int>[0, 18, 40, 18]);
    });

    test('totWarning pattern has 3 pulses (PRIMITIVE_TICK x3)', () {
      // pattern is [gap, pulse, gap, pulse, gap, pulse] -> 3 pulse entries.
      final pulses = <int>[];
      for (var i = 1; i < PttHapticFeedback.totWarningPattern.length; i += 2) {
        pulses.add(PttHapticFeedback.totWarningPattern[i]);
      }
      expect(pulses.length, 3);
    });

    test(
      'grant() never throws even with no platform vibrator channel '
      '(production default path, unmocked)',
      () async {
        await expectLater(PttHapticFeedback.grant(), completes);
      },
    );

    test(
      'denied() never throws even with no platform vibrator channel '
      '(production default path, unmocked)',
      () async {
        await expectLater(PttHapticFeedback.denied(), completes);
      },
    );

    test(
      'totWarning() never throws even with no platform vibrator channel '
      '(production default path, unmocked)',
      () async {
        await expectLater(PttHapticFeedback.totWarning(), completes);
      },
    );
  });
}
