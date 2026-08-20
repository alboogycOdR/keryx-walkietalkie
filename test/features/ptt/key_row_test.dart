import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/ptt/key_row.dart';

void main() {
  Widget harness({
    required VoidCallback onMonHoldStart,
    required VoidCallback onMonHoldEnd,
    required VoidCallback onScan,
    required VoidCallback onSayAgain,
    required VoidCallback onSettings,
    Set<PttSecondaryKey> lockedKeys = const <PttSecondaryKey>{},
    bool enabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PttKeyRow(
          onMonHoldStart: onMonHoldStart,
          onMonHoldEnd: onMonHoldEnd,
          onScan: onScan,
          onSayAgain: onSayAgain,
          onSettings: onSettings,
          lockedKeys: lockedKeys,
          enabled: enabled,
        ),
      ),
    );
  }

  testWidgets('renders all four keys', (tester) async {
    await tester.pumpWidget(
      harness(
        onMonHoldStart: () {},
        onMonHoldEnd: () {},
        onScan: () {},
        onSayAgain: () {},
        onSettings: () {},
      ),
    );

    expect(find.byKey(const Key('keryx-ptt-key-mon')), findsOneWidget);
    expect(find.byKey(const Key('keryx-ptt-key-scan')), findsOneWidget);
    expect(find.byKey(const Key('keryx-ptt-key-sayAgain')), findsOneWidget);
    expect(find.byKey(const Key('keryx-ptt-key-settings')), findsOneWidget);
  });

  testWidgets('MON exposes press-and-hold: down fires start, up fires end', (
    tester,
  ) async {
    final events = <String>[];
    await tester.pumpWidget(
      harness(
        onMonHoldStart: () => events.add('start'),
        onMonHoldEnd: () => events.add('end'),
        onScan: () {},
        onSayAgain: () {},
        onSettings: () {},
      ),
    );

    final mon = find.byKey(const Key('keryx-ptt-key-mon'));
    final gesture = await tester.startGesture(tester.getCenter(mon));
    await tester.pump();
    expect(events, <String>['start']);
    await gesture.up();
    await tester.pump();
    expect(events, <String>['start', 'end']);
  });

  testWidgets('SCAN/SAY AGN/settings fire once on tap release', (
    tester,
  ) async {
    var scanCount = 0;
    var sayAgainCount = 0;
    var settingsCount = 0;
    await tester.pumpWidget(
      harness(
        onMonHoldStart: () {},
        onMonHoldEnd: () {},
        onScan: () => scanCount++,
        onSayAgain: () => sayAgainCount++,
        onSettings: () => settingsCount++,
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-ptt-key-scan')));
    await tester.tap(find.byKey(const Key('keryx-ptt-key-sayAgain')));
    await tester.tap(find.byKey(const Key('keryx-ptt-key-settings')));
    await tester.pump();

    expect(scanCount, 1);
    expect(sayAgainCount, 1);
    expect(settingsCount, 1);
  });

  testWidgets('locked key still fires its intent on tap', (tester) async {
    var scanCount = 0;
    await tester.pumpWidget(
      harness(
        onMonHoldStart: () {},
        onMonHoldEnd: () {},
        onScan: () => scanCount++,
        onSayAgain: () {},
        onSettings: () {},
        lockedKeys: const <PttSecondaryKey>{PttSecondaryKey.scan},
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-ptt-key-scan')));
    await tester.pump();

    expect(scanCount, 1, reason: 'locked keys still emit intent (PT deny)');
    expect(find.text('SCAN ✦'), findsOneWidget);
  });

  testWidgets('disabled row ignores gestures', (tester) async {
    var scanCount = 0;
    await tester.pumpWidget(
      harness(
        onMonHoldStart: () {},
        onMonHoldEnd: () {},
        onScan: () => scanCount++,
        onSayAgain: () {},
        onSettings: () {},
        enabled: false,
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-ptt-key-scan')));
    await tester.pump();

    expect(scanCount, 0);
  });
}
