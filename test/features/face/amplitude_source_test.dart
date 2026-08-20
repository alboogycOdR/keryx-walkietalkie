import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/face/amplitude_source.dart';

void main() {
  // FaceAmplitudeSource's periodic Timer never expires on its own, so each
  // testWidgets case below must cancel it (via `source.dispose()`) before
  // the test body returns — `addTearDown` runs too late relative to
  // flutter_test's pending-timer invariant check in this SDK to catch a
  // still-ticking periodic Timer, only a Timer that has already fired/been
  // cancelled by then.
  testWidgets('stays near 0 while idle', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final source = FaceAmplitudeSource();
    final values = <double>[];
    final sub = source.stream.listen(values.add);

    source.update(const RadioState.off());
    await tester.pump(const Duration(milliseconds: 400));

    expect(values, isNotEmpty);
    expect(values.last, lessThan(0.05));

    // `source.dispose()` synchronously cancels the periodic Timer — do that
    // first. `sub.cancel()` returns a Future that (like any Future here)
    // only resolves on a subsequent pump/microtask flush inside FakeAsync,
    // which this test has none of left, so it must NOT be awaited or the
    // test hangs until flutter_test's 10-minute per-test timeout.
    source.dispose();
    unawaited(sub.cancel());
  });

  testWidgets('rises toward the active amplitude while transmitting', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final source = FaceAmplitudeSource();
    final values = <double>[];
    final sub = source.stream.listen(values.add);

    source.update(const RadioState(phase: RadioPhase.tx));
    await tester.pump(const Duration(milliseconds: 900));

    expect(values, isNotEmpty);
    expect(values.last, greaterThan(0.4));

    source.dispose();
    unawaited(sub.cancel());
  });

  testWidgets('rises while MONITOR is open even at idle phase', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    final source = FaceAmplitudeSource();
    final values = <double>[];
    final sub = source.stream.listen(values.add);

    source.update(
      const RadioState(phase: RadioPhase.idle, isMonitorOpen: true),
    );
    await tester.pump(const Duration(milliseconds: 900));

    expect(values.last, greaterThan(0.4));

    source.dispose();
    unawaited(sub.cancel());
  });

  test('emitted values never leave [0,1]', () async {
    final source = FaceAmplitudeSource();
    final values = <double>[];
    final sub = source.stream.listen(values.add);

    source.update(const RadioState(phase: RadioPhase.tx));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    source.update(const RadioState.off());
    await Future<void>.delayed(const Duration(milliseconds: 300));

    for (final v in values) {
      expect(v, inInclusiveRange(0, 1));
    }

    await sub.cancel();
    source.dispose();
  });
}
