import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/face/status_strip.dart';

void _noop() {}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required int stationCount,
    required int? signalQuality,
    required VoidCallback onStationsTap,
    VoidCallback onSettingsTap = _noop,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusStrip(
            stationCount: stationCount,
            signalQuality: signalQuality,
            modeLabel: 'AUTO',
            batteryLevel: 0.84,
            onStationsTap: onStationsTap,
            onSettingsTap: onSettingsTap,
          ),
        ),
      ),
    );
  }

  testWidgets('renders STN count and mode label (FR-067)', (tester) async {
    await pump(
      tester,
      stationCount: 3,
      signalQuality: 5,
      onStationsTap: () {},
    );
    expect(find.text('STN 3 · AUTO'), findsOneWidget);
  });

  testWidgets('tapping the STN element fires onStationsTap', (tester) async {
    var tapped = false;
    await pump(
      tester,
      stationCount: 2,
      signalQuality: 4,
      onStationsTap: () => tapped = true,
    );
    await tester.tap(find.byKey(const Key('keryx-status-strip-stn')));
    expect(tapped, isTrue);
  });

  testWidgets(
    'tapping the settings icon fires onSettingsTap (Phase 2 header kebab)',
    (tester) async {
      var tapped = false;
      await pump(
        tester,
        stationCount: 0,
        signalQuality: null,
        onStationsTap: () {},
        onSettingsTap: () => tapped = true,
      );
      await tester.tap(find.byKey(const Key('keryx-status-strip-settings')));
      expect(tapped, isTrue);
    },
  );

  testWidgets('renders battery percentage', (tester) async {
    await pump(
      tester,
      stationCount: 0,
      signalQuality: null,
      onStationsTap: () {},
    );
    expect(find.text('BAT 84%'), findsOneWidget);
  });

  testWidgets('exposes an S1-S9 semantics label when there is signal', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      stationCount: 1,
      signalQuality: 7,
      onStationsTap: () {},
    );
    expect(find.bySemanticsLabel('Signal S7'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('exposes a "No signal" semantics label with an empty roster', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      stationCount: 0,
      signalQuality: null,
      onStationsTap: () {},
    );
    expect(find.bySemanticsLabel('No signal'), findsOneWidget);
    handle.dispose();
  });
}
