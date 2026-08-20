import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/face/glass_flip_controller.dart';

void main() {
  // GlassFlipController schedules a real dart:async Timer; pumping it inside
  // testWidgets (same pattern already established by
  // test/features/tuning/stepper_button_test.dart's millisecond-accurate
  // auto-repeat assertions) lets `tester.pump(duration)` drive it
  // deterministically without a widget tree of its own.
  testWidgets('flipToStations flips to true immediately', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final controller = GlassFlipController();

    expect(controller.showStations, isFalse);
    controller.flipToStations();
    expect(controller.showStations, isTrue);

    // The 5s auto-flip Timer is still pending here — cancel it explicitly
    // (addTearDown runs too late relative to the pending-timer invariant
    // check to catch a still-ticking Timer in this SDK).
    controller.dispose();
  });

  testWidgets('auto-flips back to the glass after 5s (FR-067)', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = GlassFlipController();
    addTearDown(controller.dispose);

    controller.flipToStations();
    expect(controller.showStations, isTrue);

    await tester.pump(const Duration(seconds: 4));
    expect(controller.showStations, isTrue, reason: 'not yet at 5s');

    await tester.pump(const Duration(seconds: 2));
    expect(controller.showStations, isFalse, reason: 'past 5s, auto-flipped');
  });

  testWidgets('re-tapping while already flipped restarts the 5s window', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = GlassFlipController();
    addTearDown(controller.dispose);

    controller.flipToStations();
    await tester.pump(const Duration(seconds: 4));
    expect(controller.showStations, isTrue);

    controller.flipToStations(); // restart the window
    await tester.pump(const Duration(seconds: 4));
    expect(
      controller.showStations,
      isTrue,
      reason: 'still within the restarted 5s window',
    );

    await tester.pump(const Duration(seconds: 2));
    expect(controller.showStations, isFalse);
  });

  testWidgets('flipToGlass cancels a pending auto-flip and is idempotent', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = GlassFlipController();
    addTearDown(controller.dispose);

    controller.flipToStations();
    controller.flipToGlass();
    expect(controller.showStations, isFalse);

    // The cancelled timer must not fire later and flip something else.
    await tester.pump(const Duration(seconds: 6));
    expect(controller.showStations, isFalse);

    controller.flipToGlass(); // no-op, must not throw
    expect(controller.showStations, isFalse);
  });

  testWidgets('notifies listeners exactly on real transitions', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final controller = GlassFlipController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.flipToStations();
    expect(notifications, 1);
    controller.flipToStations(); // already true — restarts timer, no new notify
    expect(notifications, 1);
    controller.flipToGlass();
    expect(notifications, 2);
  });

  test('dispose is safe to call and prevents further notification', () {
    final controller = GlassFlipController();
    controller.dispose();
    expect(() => controller.flipToGlass(), returnsNormally);
  });
}
