import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/face/face_view.dart';
import 'package:keryx/features/ptt/ptt.dart';

void main() {
  Widget buildFace({
    RadioState? state,
    ValueListenable<double>? ringLevel,
    PttState? pttState,
    String? statusOverride,
  }) {
    return MaterialApp(
      home: FaceView(
        state: state ?? const RadioState(phase: RadioPhase.idle),
        stations: const [],
        ringLevel: ringLevel ?? ValueNotifier<double>(0),
        pttState: pttState ?? PttState.idle,
        batteryLevel: 1,
        onStep: (_) {},
        onDirectTuneRequested: () {},
        onRecallRequested: () {},
        onPttPressStart: () {},
        onPttPressEnd: () {},
        onLatchToggled: (_) {},
        onMonHoldStart: () {},
        onMonHoldEnd: () {},
        onScan: () {},
        onOpenRoster: () {},
        onSettings: () {},
        onEmergencyToggled: () {},
        statusOverride: statusOverride,
      ),
    );
  }

  testWidgets('boots to the face without throwing', (tester) async {
    await tester.pumpWidget(buildFace());
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('keryx-lcd-glass')), findsOneWidget);
  });

  testWidgets(
    'portrait vertical allocation matches the face allocation fractions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildFace());

      final bandKeys = [
        FaceView.bandKeyHeader,
        FaceView.bandKeyDisplay,
        FaceView.bandKeySteppers,
        FaceView.bandKeyDisc,
        FaceView.bandKeyRail,
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
    'the hero disc renders below 1/3 of the face height (replaces the '
    'retired knob for the "controls never occupy the top third" rule)',
    (tester) async {
      const height = 1000.0;
      tester.view.physicalSize = const Size(360, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildFace());

      final discFinder = find.byKey(const Key('keryx-ptt-disc'));
      expect(discFinder, findsOneWidget);
      final discTopY = tester.getTopLeft(discFinder).dy;
      expect(discTopY, greaterThan(height / 3));
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

  testWidgets(
    'STN tap (header) opens the roster via onOpenRoster',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FaceView(
            state: const RadioState(phase: RadioPhase.idle),
            stations: const [],
            ringLevel: ValueNotifier<double>(0),
            pttState: PttState.idle,
            batteryLevel: 1,
            onStep: (_) {},
            onDirectTuneRequested: () {},
            onRecallRequested: () {},
            onPttPressStart: () {},
            onPttPressEnd: () {},
            onLatchToggled: (_) {},
            onMonHoldStart: () {},
            onMonHoldEnd: () {},
            onScan: () {},
            onOpenRoster: () => opened++,
            onSettings: () {},
            onEmergencyToggled: () {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('keryx-status-strip-stn')));
      expect(opened, 1);

      await tester.tap(find.byKey(const Key('keryx-ptt-key-sayAgain')));
      expect(opened, 2);
    },
  );

  testWidgets('displays a channel numeral driven by RadioState', (
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

  testWidgets(
    'emergency band appears when RadioState.isEmergency is true and is '
    'absent otherwise',
    (tester) async {
      await tester.pumpWidget(buildFace());
      expect(find.byKey(const Key('keryx-emergency-band')), findsNothing);

      await tester.pumpWidget(
        buildFace(
          state: const RadioState(phase: RadioPhase.idle, isEmergency: true),
          pttState: PttState.emergency,
        ),
      );
      expect(find.byKey(const Key('keryx-emergency-band')), findsOneWidget);
      expect(find.text('EMERGENCY ACTIVE'), findsOneWidget);
    },
  );

  testWidgets(
    'PttState.emergency renders the disc in its emergency colour/legend',
    (tester) async {
      await tester.pumpWidget(buildFace(pttState: PttState.emergency));
      expect(find.text('CANCEL'), findsOneWidget);
    },
  );

  testWidgets(
    'PttState.receiving renders the disc in its RX colour/legend',
    (tester) async {
      await tester.pumpWidget(buildFace(pttState: PttState.receiving));
      expect(find.text('BUSY'), findsOneWidget);
    },
  );

  testWidgets(
    'ring level is fed straight through to the disc (no internal demo '
    'animation driving it)',
    (tester) async {
      final level = ValueNotifier<double>(0);
      await tester.pumpWidget(buildFace(ringLevel: level));
      expect(
        PttRingController.litTickCountForLevel(0),
        0,
      );
      level.value = 100;
      await tester.pump();
      expect(find.byKey(const Key('keryx-ptt-ring')), findsOneWidget);
    },
  );
}
