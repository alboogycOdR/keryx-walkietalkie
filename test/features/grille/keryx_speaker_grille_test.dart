import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/grille/grille_motion.dart';
import 'package:keryx/features/grille/keryx_speaker_grille.dart';

void main() {
  Future<KeryxSpeakerGrilleState> pumpGrille(
    WidgetTester tester, {
    required Stream<double> amplitude,
    bool live = false,
    bool? reduceMotion,
    math.Random? random,
    bool mediaQueryDisableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              disableAnimations: mediaQueryDisableAnimations,
            ),
            child: child!,
          );
        },
        home: Scaffold(
          body: SizedBox(
            height: 240,
            width: 320,
            child: KeryxSpeakerGrille(
              amplitude: amplitude,
              live: live,
              reduceMotion: reduceMotion,
              random: random ?? math.Random(1),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.state<KeryxSpeakerGrilleState>(
      find.byType(KeryxSpeakerGrille),
    );
  }

  Color slotColor(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.byKey(const Key('keryx-grille-slot-0')),
    );
    return (box.decoration as BoxDecoration).color!;
  }

  testWidgets('zero amplitude keeps every slot at rest scale', (tester) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    final state = await pumpGrille(tester, amplitude: amp.stream);

    amp.add(0);
    await tester.pump();
    await tester.pump(KeryxTheme.settleDuration);

    expect(state.lastAmplitude, 0);
    expect(state.barScales, everyElement(1));
    expect(find.byKey(const Key('keryx-grille-bar-8')), findsOneWidget);
  });

  testWidgets('amplitude above zero changes bar transforms after settle', (
    tester,
  ) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    final state = await pumpGrille(tester, amplitude: amp.stream);

    amp.add(1);
    await tester.pump();
    expect(
      state.barScales,
      everyElement(1),
      reason: 'mass: the first frame has not yet left rest',
    );

    await tester.pump(KeryxTheme.settleDuration);
    await tester.pump(const Duration(milliseconds: 16));

    expect(state.lastAmplitude, 1);
    expect(
      state.barScales.any((double s) => s != 1),
      isTrue,
      reason: 'tremble must move at least one slot off rest',
    );
  });

  testWidgets('explicit reduced-motion freezes bars but keeps the stream', (
    tester,
  ) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    final state = await pumpGrille(
      tester,
      amplitude: amp.stream,
      reduceMotion: true,
    );

    amp.add(0.8);
    await tester.pump();
    await tester.pump(KeryxTheme.settleDuration);
    await tester.pump(const Duration(milliseconds: 32));

    expect(state.lastAmplitude, 0.8);
    expect(state.barScales, everyElement(1));
  });

  testWidgets('MediaQuery.disableAnimations removes the tremble', (
    tester,
  ) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    final state = await pumpGrille(
      tester,
      amplitude: amp.stream,
      mediaQueryDisableAnimations: true,
    );

    amp.add(1);
    await tester.pump();
    await tester.pump(KeryxTheme.settleDuration);

    expect(state.lastAmplitude, 1);
    expect(state.barScales, everyElement(1));
  });

  testWidgets('live tint toggles slot colour independently of amplitude', (
    tester,
  ) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);

    await pumpGrille(tester, amplitude: amp.stream);
    expect(slotColor(tester), const Color(0xFF0D0F10));

    await pumpGrille(tester, amplitude: amp.stream, live: true);
    expect(slotColor(tester), const Color(0xFF12211A));
  });

  testWidgets('shell consumes shell900 and the theme lip', (tester) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    await pumpGrille(tester, amplitude: amp.stream);

    final shell = tester.widget<DecoratedBox>(
      find.byKey(const Key('keryx-grille-shell')),
    );
    final decoration = shell.decoration as BoxDecoration;
    expect(decoration.color, KeryxTheme.shell900);
    expect(
      decoration.boxShadow,
      containsAll(KeryxTheme.raisedMaterialEdges),
    );
  });

  testWidgets('non-finite amplitude is ignored; finite values clamp', (
    tester,
  ) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    final state = await pumpGrille(tester, amplitude: amp.stream);

    amp.add(0.4);
    await tester.pump();
    expect(state.lastAmplitude, 0.4);

    amp.add(double.nan);
    amp.add(double.infinity);
    await tester.pump();
    expect(state.lastAmplitude, 0.4);

    amp.add(4);
    await tester.pump();
    expect(state.lastAmplitude, 1);
  });

  testWidgets('nine slots match the prototype bar count', (tester) async {
    final amp = StreamController<double>.broadcast();
    addTearDown(amp.close);
    await pumpGrille(tester, amplitude: amp.stream);

    expect(GrilleMotion.barCount, 9);
    for (var i = 0; i < 9; i++) {
      expect(find.byKey(Key('keryx-grille-bar-$i')), findsOneWidget);
    }
  });
}
