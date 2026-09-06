import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/face/roster.dart';
import 'package:keryx/features/face/roster_screen.dart';

void main() {
  Widget build(ValueNotifier<List<StationInfo>> stations, {
    VoidCallback? onScan,
    VoidCallback? onExport,
  }) {
    return MaterialApp(
      home: RosterScreen(stations: stations, onScan: onScan, onExport: onExport),
    );
  }

  testWidgets('empty roster renders "NO OTHER STATIONS"', (tester) async {
    final stations = ValueNotifier<List<StationInfo>>(const []);
    await tester.pumpWidget(build(stations));
    expect(find.text('NO OTHER STATIONS'), findsOneWidget);
  });

  testWidgets(
    'live join/depart is reflected without rebuilding the screen',
    (tester) async {
      final stations = ValueNotifier<List<StationInfo>>(const [
        StationInfo(peerId: 'p1', callsign: 'ALPHA-1', signalQuality: 5),
      ]);
      await tester.pumpWidget(build(stations));
      expect(find.text('ALPHA-1'), findsOneWidget);
      expect(find.text('BRAVO-2'), findsNothing);

      stations.value = const [
        StationInfo(peerId: 'p1', callsign: 'ALPHA-1', signalQuality: 5),
        StationInfo(peerId: 'p2', callsign: 'BRAVO-2', signalQuality: 3),
      ];
      await tester.pump();
      expect(find.text('ALPHA-1'), findsOneWidget);
      expect(find.text('BRAVO-2'), findsOneWidget);

      // Depart: ALPHA-1 leaves.
      stations.value = const [
        StationInfo(peerId: 'p2', callsign: 'BRAVO-2', signalQuality: 3),
      ];
      await tester.pump();
      expect(find.text('ALPHA-1'), findsNothing);
      expect(find.text('BRAVO-2'), findsOneWidget);
    },
  );

  testWidgets('back button returns to the previous screen', (tester) async {
    final stations = ValueNotifier<List<StationInfo>>(const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RosterScreen(stations: stations),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(RosterScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(RosterScreen), findsNothing);
  });

  testWidgets('scan/export icons fire the injected callbacks', (tester) async {
    final stations = ValueNotifier<List<StationInfo>>(const []);
    var scanned = false;
    var exported = false;
    await tester.pumpWidget(
      build(stations, onScan: () => scanned = true, onExport: () => exported = true),
    );
    await tester.tap(find.byKey(const Key('keryx-roster-scan')));
    await tester.tap(find.byKey(const Key('keryx-roster-export')));
    expect(scanned, isTrue);
    expect(exported, isTrue);
  });
}
