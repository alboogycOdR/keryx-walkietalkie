import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/face/glass_flip_controller.dart';
import 'package:keryx/features/face/roster.dart';
import 'package:keryx/features/face/station_panel.dart';

void main() {
  testWidgets('shows "NO OTHER STATIONS" with an empty roster', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StationListPanel(stations: [])),
      ),
    );
    expect(find.text('NO OTHER STATIONS'), findsOneWidget);
  });

  testWidgets('renders callsign + per-station meter per FR-067', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StationListPanel(
            stations: [
              StationInfo(peerId: 'a', callsign: 'ALPHA-1', signalQuality: 5),
              StationInfo(peerId: 'b', callsign: 'BRAVO-2', signalQuality: 9),
            ],
          ),
        ),
      ),
    );
    expect(find.text('ALPHA-1'), findsOneWidget);
    expect(find.text('BRAVO-2'), findsOneWidget);
  });

  group('GlassFlipper', () {
    Future<void> pump(WidgetTester tester, GlassFlipController controller) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GlassFlipper(
              controller: controller,
              front: const Text('FRONT'),
              back: const Text('BACK'),
            ),
          ),
        ),
      );
    }

    testWidgets('shows front by default', (tester) async {
      final controller = GlassFlipController();
      addTearDown(controller.dispose);
      await pump(tester, controller);
      expect(find.text('FRONT'), findsOneWidget);
    });

    testWidgets(
      'flips to the back panel and settles using KeryxTheme.settleDuration',
      (tester) async {
        final controller = GlassFlipController();
        await pump(tester, controller);

        controller.flipToStations();
        await tester.pump(); // start the animation
        await tester.pump(const Duration(milliseconds: 320));
        await tester.pumpAndSettle();

        expect(find.text('BACK'), findsOneWidget);

        // The 5s auto-flip-back Timer is still pending here — cancel it
        // explicitly (addTearDown runs too late relative to the
        // pending-timer invariant check to catch a still-ticking Timer in
        // this SDK).
        controller.dispose();
      },
    );

    testWidgets('auto flip-back (5s) turns the glass back to the front', (
      tester,
    ) async {
      final controller = GlassFlipController();
      addTearDown(controller.dispose);
      await pump(tester, controller);

      controller.flipToStations();
      await tester.pumpAndSettle();
      expect(find.text('BACK'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.text('FRONT'), findsOneWidget);
    });
  });
}
