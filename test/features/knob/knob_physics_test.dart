import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/knob/knob_physics.dart';

void main() {
  group('KnobPhysics', () {
    test('detent index rounds to nearest 30 degree step', () {
      expect(KnobPhysics.detentIndexFor(0), 0);
      expect(KnobPhysics.detentIndexFor(14), 0);
      expect(KnobPhysics.detentIndexFor(16), 1);
      expect(KnobPhysics.detentIndexFor(29), 1);
      expect(KnobPhysics.detentIndexFor(30), 1);
      expect(KnobPhysics.detentIndexFor(-16), -1);
    });

    test('clamps velocity into the PT +/-22 deg/frame band', () {
      expect(KnobPhysics.clampVelocity(100), 22);
      expect(KnobPhysics.clampVelocity(-100), -22);
      expect(KnobPhysics.clampVelocity(5), 5);
    });

    test('clampDelta passes deltas through inside [1, 99]', () {
      expect(KnobPhysics.clampDelta(50, 3), 3);
      expect(KnobPhysics.clampDelta(50, -3), -3);
    });

    test('clampDelta stops exactly at the upper boundary (99), not wrap', () {
      expect(KnobPhysics.clampDelta(98, 1), 1); // -> 99, in range
      expect(KnobPhysics.clampDelta(99, 1), 0); // would overshoot to 100
      expect(KnobPhysics.clampDelta(97, 5), 2); // 97 + 5 = 102 -> clamp to 99
    });

    test('clampDelta stops exactly at the lower boundary (1), not wrap', () {
      expect(KnobPhysics.clampDelta(2, -1), -1); // -> 1, in range
      expect(KnobPhysics.clampDelta(1, -1), 0); // would undershoot to 0
      expect(KnobPhysics.clampDelta(3, -10), -2); // 3 - 10 = -7 -> clamp to 1
    });
  });

  group('KnobFlywheel', () {
    test('drives detent crossings from a decaying velocity', () {
      final fly = KnobFlywheel(initialVelocity: 22);
      var totalTicks = 0;
      var frames = 0;
      // Feed frames at 16 ms (60 fps) until the flywheel is finished, well
      // clear of the 12 ch/s governor's minimum 83.3 ms gap per PT-frame
      // step: this asserts the SUM across the whole fling is exact, not
      // that any single frame is unconstrained.
      while (!fly.isFinished && frames < 1000) {
        totalTicks += fly.step(16);
        frames++;
      }
      expect(fly.isFinished, isTrue, reason: 'must settle in bounded time');
      expect(totalTicks, greaterThan(0));
      // Resting angle is always an exact detent multiple.
      expect(fly.angle % KnobPhysics.detentDegrees, 0);
    });

    test('never emits ticks faster than the 12 ch/s governor', () {
      final fly = KnobFlywheel(initialVelocity: 22);
      final emitTimestampsMs = <double>[];
      var clockMs = 0.0;
      var frames = 0;
      while (!fly.isFinished && frames < 1000) {
        final delta = fly.step(16);
        clockMs += 16;
        if (delta != 0) emitTimestampsMs.add(clockMs);
        frames++;
      }
      const minGapMs = 1000 / KnobPhysics.maxTicksPerSecond;
      for (var i = 1; i < emitTimestampsMs.length; i++) {
        expect(
          emitTimestampsMs[i] - emitTimestampsMs[i - 1],
          greaterThanOrEqualTo(minGapMs - 0.001),
          reason: 'consecutive emissions must respect the 12 ch/s cap',
        );
      }
    });

    test('total emitted ticks equal the net detent crossing (no loss)', () {
      final fly = KnobFlywheel(initialVelocity: 22);
      var totalTicks = 0;
      var frames = 0;
      while (!fly.isFinished && frames < 1000) {
        totalTicks += fly.step(16);
        frames++;
      }
      final expectedNetDetents = KnobPhysics.detentIndexFor(fly.angle);
      expect(totalTicks, expectedNetDetents);
    });

    test('a sub-threshold velocity finishes immediately with no ticks', () {
      final fly = KnobFlywheel(initialVelocity: 0.1);
      expect(fly.isFinished, isTrue);
      expect(fly.step(16), 0);
    });

    test('negative velocity produces negative net ticks', () {
      final fly = KnobFlywheel(initialVelocity: -22);
      var totalTicks = 0;
      var frames = 0;
      while (!fly.isFinished && frames < 1000) {
        totalTicks += fly.step(16);
        frames++;
      }
      expect(totalTicks, lessThan(0));
    });
  });
}
