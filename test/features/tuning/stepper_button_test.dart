import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/tuning/stepper_button.dart';

void main() {
  Widget harness({
    required StepDirection direction,
    required int channel,
    required ValueChanged<int> onStep,
    VoidCallback? onLongPress,
    bool enabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChStepperButton(
          direction: direction,
          channel: channel,
          onStep: onStep,
          onLongPress: onLongPress,
          enabled: enabled,
        ),
      ),
    );
  }

  group('single tap', () {
    testWidgets('CH▲ emits exactly one +1 step on quick tap', (tester) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(
          direction: StepDirection.up,
          channel: 5,
          onStep: deltas.add,
        ),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      expect(deltas, <int>[1]);
    });

    testWidgets('CH▼ emits exactly one -1 step on quick tap', (tester) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(
          direction: StepDirection.down,
          channel: 5,
          onStep: deltas.add,
        ),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-down'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      expect(deltas, <int>[-1]);
    });

    testWidgets('a disabled button emits nothing', (tester) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(
          direction: StepDirection.up,
          channel: 5,
          onStep: deltas.add,
          enabled: false,
        ),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump();

      expect(deltas, isEmpty);
    });
  });

  group('accelerating auto-repeat (PT stepper(), L327-336)', () {
    testWidgets(
      'holding fires ticks at 0ms, 420ms, then accelerating (213ms, 175ms)',
      (tester) async {
        final deltas = <int>[];
        await tester.pumpWidget(
          harness(direction: StepDirection.up, channel: 1, onStep: deltas.add),
        );

        final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
        final gesture = await tester.startGesture(tester.getCenter(key));
        await tester.pump(); // immediate tick
        expect(deltas.length, 1, reason: 'tick fires synchronously on press');

        await tester.pump(const Duration(milliseconds: 420));
        expect(deltas.length, 2, reason: 'first repeat at the 420ms delay');

        await tester.pump(const Duration(milliseconds: 213));
        expect(
          deltas.length,
          3,
          reason: 'second repeat at 260*0.82≈213ms — faster than 420ms',
        );

        await tester.pump(const Duration(milliseconds: 175));
        expect(
          deltas.length,
          4,
          reason: 'third repeat at 213*0.82≈175ms — faster still',
        );

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets('releasing cancels the repeat timer — no further ticks', (
      tester,
    ) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(direction: StepDirection.up, channel: 1, onStep: deltas.add),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(milliseconds: 420));
      expect(deltas.length, 2);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 2000));

      expect(deltas.length, 2, reason: 'release must stop auto-repeat');
    });
  });

  group('domain clamp at the boundary (follow-up k: CLAMP, not wrap)', () {
    testWidgets('CH▲ stops emitting once channel 99 is reached', (
      tester,
    ) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(direction: StepDirection.up, channel: 99, onStep: deltas.add),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        deltas,
        isEmpty,
        reason: 'already at the ceiling — clamp yields delta 0, never wraps to 1',
      );
    });

    testWidgets('CH▼ stops emitting once channel 1 is reached', (
      tester,
    ) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(direction: StepDirection.down, channel: 1, onStep: deltas.add),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-down'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        deltas,
        isEmpty,
        reason: 'already at the floor — clamp yields delta 0, never wraps to 99',
      );
    });

    testWidgets('repeated holding at 98 emits exactly one tick then stops', (
      tester,
    ) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(direction: StepDirection.up, channel: 98, onStep: deltas.add),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));
      await tester.pump(const Duration(milliseconds: 213));
      await gesture.up();
      await tester.pump();

      expect(deltas, <int>[1], reason: '98→99 then clamp holds at 99');
    });
  });

  group('CH▼ long-press quick-recall (FR-009) vs. auto-repeat overlap', () {
    testWidgets(
      'a hold shorter than 600ms never fires onLongPress',
      (tester) async {
        var longPressed = 0;
        final deltas = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChStepperButton(
                direction: StepDirection.down,
                channel: 50,
                onStep: deltas.add,
                onLongPress: () => longPressed++,
              ),
            ),
          ),
        );

        final key = find.byKey(const ValueKey<String>('keryx-stepper-down'));
        final gesture = await tester.startGesture(tester.getCenter(key));
        await tester.pump(const Duration(milliseconds: 400));
        await gesture.up();
        await tester.pump();

        expect(longPressed, 0);
      },
    );

    testWidgets(
      'a hold crossing 600ms fires onLongPress once and stops auto-repeat',
      (tester) async {
        var longPressed = 0;
        final deltas = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ChStepperButton(
                direction: StepDirection.down,
                channel: 50,
                onStep: deltas.add,
                onLongPress: () => longPressed++,
              ),
            ),
          ),
        );

        final key = find.byKey(const ValueKey<String>('keryx-stepper-down'));
        final gesture = await tester.startGesture(tester.getCenter(key));
        await tester.pump(const Duration(milliseconds: 600));

        expect(longPressed, 1);
        // The immediate tick (0ms) and the first repeat (420ms) both landed
        // before the 600ms threshold — disclosed, non-blocking overlap
        // (see ChStepperButton's class dartdoc).
        expect(deltas.length, 2);

        // Auto-repeat must be cancelled once recall fires: holding well past
        // the next would-be repeat slot must not add a third tick.
        await tester.pump(const Duration(milliseconds: 500));
        expect(deltas.length, 2, reason: 'auto-repeat stops once recall opens');

        await gesture.up();
        await tester.pump();
        expect(longPressed, 1, reason: 'release must not re-fire recall');
      },
    );

    testWidgets('CH▲ (no onLongPress) never triggers a long-press path', (
      tester,
    ) async {
      final deltas = <int>[];
      await tester.pumpWidget(
        harness(direction: StepDirection.up, channel: 50, onStep: deltas.add),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final gesture = await tester.startGesture(tester.getCenter(key));
      await tester.pump(const Duration(milliseconds: 900));
      await gesture.up();
      await tester.pump();

      // No crash, and auto-repeat kept running normally the whole time.
      expect(deltas.length, greaterThan(1));
    });
  });

  group('accessibility (FR-106)', () {
    testWidgets('CH▲ exposes a 48dp+ target and a TalkBack label', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(direction: StepDirection.up, channel: 5, onStep: (_) {}),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      final size = tester.getSize(key);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      final semantics = tester.getSemantics(key);
      expect(semantics.label, 'Channel up');
    });

    testWidgets('CH▼ exposes a 48dp+ target and a TalkBack label', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(direction: StepDirection.down, channel: 5, onStep: (_) {}),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-down'));
      final size = tester.getSize(key);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      final semantics = tester.getSemantics(key);
      expect(semantics.label, 'Channel down');
    });

    testWidgets('a custom semanticsLabel overrides the default', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChStepperButton(
              direction: StepDirection.up,
              channel: 5,
              onStep: (_) {},
              semanticsLabel: 'Custom label',
            ),
          ),
        ),
      );

      final key = find.byKey(const ValueKey<String>('keryx-stepper-up'));
      expect(tester.getSemantics(key).label, 'Custom label');
    });
  });
}
