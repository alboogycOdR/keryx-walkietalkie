import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/face/face_view.dart';
import 'package:keryx/features/face/glass_flip_controller.dart';
import 'package:keryx/features/knob/knob.dart';
import 'package:keryx/features/ptt/ptt.dart';

void main() {
  Widget buildFace({
    RadioState? state,
    GlassFlipController? flipController,
    String? statusOverride,
  }) {
    return MaterialApp(
      home: FaceView(
        state: state ?? const RadioState(phase: RadioPhase.idle),
        stations: const [],
        amplitude: const Stream<double>.empty(),
        flipController: flipController ?? GlassFlipController(),
        pttState: PttState.idle,
        batteryLevel: 1,
        onDetent: (_) {},
        onStep: (_) {},
        onDirectTuneRequested: () {},
        onRecallRequested: () {},
        onPttPressStart: () {},
        onPttPressEnd: () {},
        onLatchToggled: (_) {},
        onMonHoldStart: () {},
        onMonHoldEnd: () {},
        onScan: () {},
        onSayAgain: () {},
        onSettings: () {},
        onEmergencyToggled: () {},
        statusOverride: statusOverride,
      ),
    );
  }

  setUp(() {});

  tearDown(() {});

  testWidgets('boots to the face without throwing', (tester) async {
    await tester.pumpWidget(buildFace());
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('keryx-lcd-glass')), findsOneWidget);
  });

  testWidgets(
    'portrait vertical allocation matches DS §4 fractions '
    '(status 6% / glass 18% / grille 26% / controls 22% / ptt 22% / safe 6%)',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildFace());

      final bandKeys = [
        FaceView.bandKeyStatus,
        FaceView.bandKeyGlass,
        FaceView.bandKeyGrille,
        FaceView.bandKeyControls,
        FaceView.bandKeyPtt,
        FaceView.bandKeySafeArea,
      ];
      final flexibles = bandKeys
          .map((key) => tester.widget<Expanded>(find.byKey(key)))
          .toList();

      final a = KeryxTheme.faceAllocation;
      final expectedFractions = [
        a.status,
        a.glass,
        a.grille,
        a.controls,
        a.ptt,
        a.safeArea,
      ];
      final totalFlex = flexibles.fold<int>(0, (sum, e) => sum + e.flex);
      for (var i = 0; i < flexibles.length; i++) {
        final actualFraction = flexibles[i].flex / totalFlex;
        expect(
          actualFraction,
          closeTo(expectedFractions[i], 0.001),
          reason: 'band $i fraction mismatch',
        );
      }
    },
  );

  testWidgets(
    'controls never occupy the top third (DS §4) — the control cluster '
    'renders below 1/3 of the face height',
    (tester) async {
      const height = 1000.0;
      tester.view.physicalSize = const Size(360, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildFace());

      final knobFinder = find.byType(KeryxTuningKnob);
      expect(knobFinder, findsOneWidget);
      final knobTopY = tester.getTopLeft(knobFinder).dy;
      expect(knobTopY, greaterThan(height / 3));
    },
  );

  testWidgets('landscape renders "brick on its side" without throwing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildFace());
    expect(tester.takeException(), isNull);
    expect(find.byType(Row), findsWidgets);
    expect(find.byKey(const Key('keryx-lcd-glass')), findsOneWidget);
  });

  testWidgets('STN tap flips the glass to the station list', (tester) async {
    final flipController = GlassFlipController();
    await tester.pumpWidget(buildFace(flipController: flipController));
    await tester.tap(find.byKey(const Key('keryx-status-strip-stn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keryx-station-panel')), findsOneWidget);

    // The 5s auto-flip-back Timer the tap just started is still pending
    // here — cancel it explicitly (addTearDown runs too late relative to
    // the pending-timer invariant check to catch a still-ticking Timer in
    // this SDK).
    flipController.dispose();
  });

  testWidgets('displays a channel/code numeral driven by RadioState', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildFace(
        state: const RadioState(phase: RadioPhase.idle, channel: 42, privacyCode: 7),
      ),
    );
    expect(find.textContaining('42'), findsWidgets);
  });

  testWidgets(
    'TASK-038: statusOverride replaces the normal status line on the glass',
    (tester) async {
      await tester.pumpWidget(
        buildFace(
          state: const RadioState(phase: RadioPhase.boot),
          statusOverride: 'MIC REQUIRED',
        ),
      );
      expect(find.text('MIC REQUIRED'), findsOneWidget);
      // The ordinary boot-phase status line text must not also be present.
      expect(find.text('CHANNEL CLEAR'), findsNothing);
    },
  );

  testWidgets(
    'null statusOverride (the default) leaves the ordinary status line '
    'exactly as before',
    (tester) async {
      await tester.pumpWidget(buildFace());
      expect(find.text('CHANNEL CLEAR'), findsOneWidget);
    },
  );
}
