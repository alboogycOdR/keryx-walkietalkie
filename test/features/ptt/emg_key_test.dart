import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/ptt/emg_key.dart';

void main() {
  testWidgets('long-press below 600ms threshold does not fire', (
    tester,
  ) async {
    var toggled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmgKey(onEmergencyToggled: () => toggled++),
        ),
      ),
    );

    final key = find.byKey(const Key('keryx-emg-key'));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();

    expect(toggled, 0);
  });

  testWidgets('long-press crossing 600ms threshold (PT L386-388) fires once', (
    tester,
  ) async {
    var toggled = 0;
    final widgetKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmgKey(key: widgetKey, onEmergencyToggled: () => toggled++),
        ),
      ),
    );

    final key = find.byKey(const Key('keryx-emg-key'));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump(const Duration(milliseconds: 600));

    expect(toggled, 1);
    expect(tester.state<EmgKeyState>(find.byKey(widgetKey)).isArmed, isTrue);

    await gesture.up();
    await tester.pump();
    expect(toggled, 1, reason: 'release must not re-fire');
  });

  testWidgets('releasing before threshold cancels the arm timer cleanly', (
    tester,
  ) async {
    var toggled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmgKey(onEmergencyToggled: () => toggled++),
        ),
      ),
    );

    final key = find.byKey(const Key('keryx-emg-key'));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    // Let any (correctly-cancelled) timer's original deadline pass.
    await tester.pump(const Duration(milliseconds: 400));

    expect(toggled, 0);
  });

  testWidgets('disabled EmgKey ignores gestures', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmgKey(onEmergencyToggled: () => toggled++, enabled: false),
        ),
      ),
    );

    final key = find.byKey(const Key('keryx-emg-key'));
    final gesture = await tester.startGesture(tester.getCenter(key));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pump();

    expect(toggled, 0);
  });
}
