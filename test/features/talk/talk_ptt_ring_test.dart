import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/features/talk/talk_ptt_ring.dart';

final Finder _ringRoot = find.byKey(const Key('keryx-talk-ptt-disc'));
final Finder _ringPaint = find.descendant(
  of: _ringRoot,
  matching: find.byType(CustomPaint),
);

void main() {
  Widget buildRing({
    TalkPttRingTreatment treatment = TalkPttRingTreatment.ready,
    MeterLevel meterLevel = MeterLevel.decorative,
    bool reducedMotion = false,
    bool enabled = true,
    required VoidCallback onStart,
    required VoidCallback onEnd,
  }) => MaterialApp(
    home: Scaffold(
      body: TalkPttRing(
        enabled: enabled,
        treatment: treatment,
        meterLevel: meterLevel,
        reducedMotion: reducedMotion,
        semanticStatus: 'Channel clear',
        ringColor: const Color(0xfff0b44c),
        faceColor: const Color(0xff1b2028),
        glyphColor: const Color(0xfff4f6f8),
        neutralRingColor: const Color(0xff566272),
        onHoldStart: onStart,
        onHoldEnd: onEnd,
      ),
    ),
  );

  test('sizeFor clamps at the specified phone widths', () {
    expect(TalkPttRing.sizeFor(320), closeTo(249.6, .001));
    expect(TalkPttRing.sizeFor(360), closeTo(280.8, .001));
    expect(TalkPttRing.sizeFor(412), 300);
    expect(TalkPttRing.sizeFor(800), 300);
    expect(TalkPttRing.sizeFor(1), 96);
  });

  test('glow is measured-only and scales with the audio level', () {
    const color = Color(0xfff0b44c);
    expect(TalkPttRing.glowFor(MeterLevel.decorative, color), isEmpty);
    final low = TalkPttRing.glowFor(const MeasuredMeterLevel(10), color).single;
    final high = TalkPttRing.glowFor(
      const MeasuredMeterLevel(90),
      color,
    ).single;
    expect(high.blurRadius, greaterThan(low.blurRadius));
    expect(high.color.a, greaterThan(low.color.a));
  });

  testWidgets('pointer holds are idempotent and cancellation ends once', (
    tester,
  ) async {
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(
      buildRing(onStart: () => starts++, onEnd: () => ends++),
    );
    final center = tester.getCenter(
      find.byKey(const Key('keryx-talk-ptt-disc')),
    );
    final first = await tester.startGesture(center, pointer: 1);
    await tester.pump();
    final second = await tester.startGesture(center, pointer: 2);
    await tester.pump();
    expect(starts, 1);
    await first.cancel();
    await tester.pump();
    await second.up();
    await tester.pump();
    expect(ends, 1);
  });

  testWidgets('semantic and keyboard alternatives toggle the same callbacks', (
    tester,
  ) async {
    var starts = 0;
    var ends = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildRing(onStart: () => starts++, onEnd: () => ends++),
    );
    final Semantics node = tester.widget<Semantics>(
      find.byKey(const Key('keryx-talk-ptt-disc-semantics')),
    );
    expect(node.properties.label, 'Push to talk');
    expect(node.properties.value, 'Channel clear');
    expect(node.properties.customSemanticsActions, hasLength(1));
    node.properties.customSemanticsActions!.values.single();
    await tester.pump();
    expect(starts, 1);
    Focus.of(tester.element(_ringRoot)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(ends, 1);
    semantics.dispose();
  });

  testWidgets('reduced motion keeps requesting and denied states static', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildRing(
        treatment: TalkPttRingTreatment.requesting,
        reducedMotion: true,
        onStart: () {},
        onEnd: () {},
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(
      buildRing(
        treatment: TalkPttRingTreatment.deniedFlash,
        reducedMotion: true,
        onStart: () {},
        onEnd: () {},
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('every treatment supplies its specified painter ring colour', (
    tester,
  ) async {
    for (final treatment in TalkPttRingTreatment.values) {
      await tester.pumpWidget(
        buildRing(treatment: treatment, onStart: () {}, onEnd: () {}),
      );
      await tester.pump();
      final CustomPaint paint = tester.widget<CustomPaint>(
        _ringPaint,
      );
      final TalkPttRingPainter painter = paint.painter! as TalkPttRingPainter;
      final bool neutral =
          treatment == TalkPttRingTreatment.deniedFlash ||
          treatment == TalkPttRingTreatment.neutral;
      expect(
        painter.ringColor,
        neutral ? const Color(0xff566272) : const Color(0xfff0b44c),
      );
      expect(find.text('Channel clear'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('disabled ring dims its painter colour and rejects all inputs', (
    tester,
  ) async {
    var starts = 0;
    var ends = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      buildRing(enabled: false, onStart: () => starts++, onEnd: () => ends++),
    );
    final CustomPaint paint = tester.widget<CustomPaint>(
      _ringPaint,
    );
    expect(
      (paint.painter! as TalkPttRingPainter).ringColor,
      const Color(0xfff0b44c).withValues(alpha: .35),
    );
    final center = tester.getCenter(
      find.byKey(const Key('keryx-talk-ptt-disc')),
    );
    final gesture = await tester.startGesture(center);
    await gesture.up();
    final Semantics node = tester.widget<Semantics>(
      find.byKey(const Key('keryx-talk-ptt-disc-semantics')),
    );
    node.properties.customSemanticsActions!.values.single();
    Focus.of(tester.element(_ringRoot)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(starts, 0);
    expect(ends, 0);
    semantics.dispose();
  });

  testWidgets('keyboard activation requires deliberate PTT focus', (tester) async {
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(
      buildRing(onStart: () => starts++, onEnd: () => ends++),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(starts, 0);
    Focus.of(tester.element(_ringRoot)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(starts, 1);
    expect(ends, 0);
  });

  testWidgets('requesting sweeps and denied flash settles after its one shot', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildRing(
        treatment: TalkPttRingTreatment.requesting,
        onStart: () {},
        onEnd: () {},
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(
      buildRing(
        treatment: TalkPttRingTreatment.deniedFlash,
        onStart: () {},
        onEnd: () {},
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('decorative telemetry at rest schedules no animation', (tester) async {
    await tester.pumpWidget(
      buildRing(onStart: () {}, onEnd: () {}),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
