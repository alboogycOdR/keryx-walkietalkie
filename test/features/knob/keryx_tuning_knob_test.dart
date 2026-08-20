import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/knob/knob_widget.dart';

/// Minimal host harness: feeds `onDetent` deltas back into `channel`, the
/// same round-trip a real reducer-backed host would perform (this widget
/// owns no tuning state itself).
class _Harness extends StatefulWidget {
  const _Harness({
    required this.initialChannel,
    required this.onDetent,
    this.enabled = true,
  });

  final int initialChannel;
  final void Function(int delta) onDetent;
  final bool enabled;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _channel = widget.initialChannel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: KeryxTuningKnob(
            channel: _channel,
            enabled: widget.enabled,
            // Injected no-op haptic seam: avoids depending on a real
            // platform vibrator channel in tests (production leaves this
            // unset, exercising KnobHapticFeedback.click by default —
            // covered separately in knob_feedback_test.dart).
            onHapticClick: () async {},
            onDetent: (delta) {
              setState(() => _channel += delta);
              widget.onDetent(delta);
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  Offset pointAt(Offset center, double radius, double degrees) {
    final rad = degrees * math.pi / 180;
    return center + Offset(math.cos(rad), math.sin(rad)) * radius;
  }

  testWidgets('drag through 3 detents emits a net channel delta of 3', (
    tester,
  ) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      _Harness(initialChannel: 50, onDetent: deltas.add),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('keryx-knob-paint')));
    const radius = 40.0;

    final gesture = await tester.startGesture(pointAt(center, radius, -90));
    await tester.pump();
    // Move through detent CENTERS (multiples of 30°) — waypoints exactly at
    // the halfway tie boundary (odd multiples of 15°) are one ULP-sensitive
    // to atan2/cos/sin floating-point noise and must be avoided in a
    // deterministic test.
    for (final deg in <double>[-60, -30, 0]) {
      await gesture.moveTo(pointAt(center, radius, deg));
      await tester.pump();
    }
    // Re-touch the same point so the pointer's instantaneous velocity is
    // zero at release: real drags naturally slow before lifting, but this
    // test's synthetic moves land back-to-back in near-zero wall-clock
    // time, which would otherwise read as a very fast (capped) fling and
    // hand off to the flywheel for one extra tick after release — this
    // test is asserting the DIRECT-DRAG count, covered on its own by the
    // dedicated fling test below.
    await gesture.moveTo(pointAt(center, radius, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(deltas.every((d) => d != 0), isTrue);
    expect(deltas.fold<int>(0, (a, b) => a + b), 3);
  });

  testWidgets('dragging the opposite way emits negative deltas', (
    tester,
  ) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      _Harness(initialChannel: 50, onDetent: deltas.add),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('keryx-knob-paint')));
    const radius = 40.0;

    final gesture = await tester.startGesture(pointAt(center, radius, 0));
    await tester.pump();
    for (final deg in <double>[-30, -60]) {
      await gesture.moveTo(pointAt(center, radius, deg));
      await tester.pump();
    }
    // See the zero-velocity note in the previous test — same reasoning.
    await gesture.moveTo(pointAt(center, radius, -60));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(deltas.fold<int>(0, (a, b) => a + b), -2);
  });

  testWidgets('clamps at the upper channel boundary instead of wrapping', (
    tester,
  ) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      _Harness(initialChannel: 99, onDetent: deltas.add),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('keryx-knob-paint')));
    const radius = 40.0;

    final gesture = await tester.startGesture(pointAt(center, radius, -90));
    await tester.pump();
    for (final deg in <double>[-60, -30]) {
      await gesture.moveTo(pointAt(center, radius, deg));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(
      deltas,
      isEmpty,
      reason: 'channel is already at maximum (99); CLAMP must not wrap to 1',
    );
  });

  testWidgets('clamps at the lower channel boundary instead of wrapping', (
    tester,
  ) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      _Harness(initialChannel: 1, onDetent: deltas.add),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('keryx-knob-paint')));
    const radius = 40.0;

    final gesture = await tester.startGesture(pointAt(center, radius, 0));
    await tester.pump();
    for (final deg in <double>[-30, -60]) {
      await gesture.moveTo(pointAt(center, radius, deg));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(
      deltas,
      isEmpty,
      reason: 'channel is already at minimum (1); CLAMP must not wrap to 99',
    );
  });

  testWidgets(
    'a slow release snaps any leftover sub-detent angle to the nearest '
    'detent (TS §6.2 critically-damped settle)',
    (tester) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        _Harness(initialChannel: 50, onDetent: deltas.add),
      );
      await tester.pump();

      final knobState = tester.state<KeryxTuningKnobState>(
        find.byType(KeryxTuningKnob),
      );
      final center = tester.getCenter(
        find.byKey(const Key('keryx-knob-paint')),
      );
      const radius = 40.0;

      final gesture = await tester.startGesture(
        pointAt(center, radius, -90),
      );
      await tester.pump();
      // One 20° jump crosses exactly one detent boundary and rests 10°
      // short of the next detent centre (-60), leaving a real sub-detent
      // residual to snap away.
      await gesture.moveTo(pointAt(center, radius, -70));
      await tester.pump();
      // Zero-velocity re-touch — see the earlier tests' note — so release
      // resolves as a slow settle, not a fling.
      await gesture.moveTo(pointAt(center, radius, -70));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // The widget's internal angle accumulates from 0 (not the pointer's
      // absolute starting angle) — a +20° pointer delta lands the internal
      // angle at 20°, one detent (30°) away from centre, which is where it
      // must snap to.
      expect(knobState.isFlinging, isFalse);
      expect(deltas.fold<int>(0, (a, b) => a + b), 1);
      expect(knobState.angle, closeTo(30, 1e-6));
    },
  );

  testWidgets('disabled knob ignores drags entirely', (tester) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      _Harness(initialChannel: 50, onDetent: deltas.add, enabled: false),
    );
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('keryx-knob-paint')));
    const radius = 40.0;

    final gesture = await tester.startGesture(pointAt(center, radius, -90));
    await tester.pump();
    for (final deg in <double>[-60, -30, 0]) {
      await gesture.moveTo(pointAt(center, radius, deg));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();

    expect(deltas, isEmpty);
  });

  testWidgets('a fast release hands off to the flywheel, which settles on '
      'a detent', (tester) async {
    final deltas = <int>[];
    await tester.pumpWidget(
      _Harness(initialChannel: 10, onDetent: deltas.add),
    );
    await tester.pump();

    final knobState = tester.state<KeryxTuningKnobState>(
      find.byType(KeryxTuningKnob),
    );
    final center = tester.getCenter(find.byKey(const Key('keryx-knob-paint')));
    const radius = 40.0;

    final gesture = await tester.startGesture(pointAt(center, radius, -90));
    await tester.pump();
    await gesture.moveTo(pointAt(center, radius, -60));
    await tester.pump(const Duration(milliseconds: 8));
    await gesture.moveTo(pointAt(center, radius, -30));
    await tester.pump(const Duration(milliseconds: 8));
    await gesture.up();
    await tester.pump();

    expect(
      knobState.isFlinging,
      isTrue,
      reason: 'a fast drag release must hand off to the flywheel, not stop '
          'dead',
    );

    for (var i = 0; i < 200 && knobState.isFlinging; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(knobState.isFlinging, isFalse);
    expect(knobState.angle % 30, closeTo(0, 1e-6));
    expect(
      deltas.fold<int>(0, (a, b) => a + b),
      knobState.angle ~/ 30,
      reason: 'every emitted delta, drag + fling, must sum to the net '
          'detents actually crossed',
    );
  });

  testWidgets('semantics expose the knob as a slider labelled with channel', (
    tester,
  ) async {
    await tester.pumpWidget(_Harness(initialChannel: 42, onDetent: (_) {}));
    await tester.pump();

    expect(
      tester.getSemantics(find.byType(KeryxTuningKnob)),
      matchesSemantics(
        isSlider: true,
        label: 'Tuning knob',
        value: 'Channel 42',
      ),
    );
  });
}
