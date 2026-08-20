import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/knob/knob_feedback.dart';

void main() {
  group('KnobHapticFeedback', () {
    test('click duration matches TS §6.2 8 ms mechanical tick sample', () {
      expect(KnobHapticFeedback.clickDurationMs, 8);
    });

    test('click amplitude matches TS §6.4 PRIMITIVE_CLICK scale 0.6', () {
      expect(KnobHapticFeedback.clickAmplitude, (255 * 0.6).round());
    });

    test(
      'click() never throws even with no platform vibrator channel '
      '(production default path, unmocked)',
      () async {
        // No platform binding is registered for package:vibration in this
        // test environment, so the underlying platform call fails; click()
        // must swallow it rather than propagate.
        await expectLater(KnobHapticFeedback.click(), completes);
      },
    );
  });
}
