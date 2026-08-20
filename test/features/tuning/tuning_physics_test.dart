import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/tuning/tuning_physics.dart';

void main() {
  group('TuningPhysics domain bounds', () {
    test('matches the ratified 1-99 / 00-38 CLAMP domain', () {
      expect(TuningPhysics.minimumChannel, 1);
      expect(TuningPhysics.maximumChannel, 99);
      expect(TuningPhysics.minimumPrivacyCode, 0);
      expect(TuningPhysics.maximumPrivacyCode, 38);
    });

    test('isValidChannel is true only inside 1-99 inclusive', () {
      expect(TuningPhysics.isValidChannel(0), isFalse);
      expect(TuningPhysics.isValidChannel(1), isTrue);
      expect(TuningPhysics.isValidChannel(99), isTrue);
      expect(TuningPhysics.isValidChannel(100), isFalse);
    });

    test('isValidPrivacyCode is true only inside 00-38 inclusive', () {
      expect(TuningPhysics.isValidPrivacyCode(-1), isFalse);
      expect(TuningPhysics.isValidPrivacyCode(0), isTrue);
      expect(TuningPhysics.isValidPrivacyCode(38), isTrue);
      expect(TuningPhysics.isValidPrivacyCode(39), isFalse);
    });
  });

  group('TuningPhysics auto-repeat constants', () {
    test('matches PT stepper() literals (L327-336)', () {
      expect(TuningPhysics.initialRepeatDelay, const Duration(milliseconds: 420));
      expect(TuningPhysics.initialRepeatRateMs, 260);
      expect(TuningPhysics.repeatAcceleration, 0.82);
      expect(TuningPhysics.minRepeatRateMs, 60);
    });

    test('recallLongPressThreshold matches EmgKey convention (600ms)', () {
      expect(
        TuningPhysics.recallLongPressThreshold,
        const Duration(milliseconds: 600),
      );
    });
  });

  group('TuningPhysics.clampChannelDelta', () {
    test('passes through an in-domain delta unchanged', () {
      expect(TuningPhysics.clampChannelDelta(50, 1), 1);
      expect(TuningPhysics.clampChannelDelta(50, -1), -1);
    });

    test('clamps to 0 at the maximum boundary (no wrap to 1)', () {
      expect(TuningPhysics.clampChannelDelta(99, 1), 0);
    });

    test('clamps to 0 at the minimum boundary (no wrap to 99)', () {
      expect(TuningPhysics.clampChannelDelta(1, -1), 0);
    });

    test('clamps a large delta to exactly reach the boundary', () {
      expect(TuningPhysics.clampChannelDelta(95, 10), 4);
      expect(TuningPhysics.clampChannelDelta(5, -10), -4);
    });
  });
}
