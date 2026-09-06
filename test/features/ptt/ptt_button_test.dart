import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/ptt/key_row.dart';
import 'package:keryx/features/ptt/ptt_button.dart';
import 'package:keryx/features/ptt/ptt_state.dart';

Widget _disc(PttState state, PttRingController controller) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: PttButton(
        state: state,
        ringController: controller,
        onPressStart: () {},
        onPressEnd: () {},
        onLatchToggled: (_) {},
        onGrantHaptic: () async {},
        onDeniedHaptic: () async {},
      ),
    ),
  ),
);

void main() {
  testWidgets('hero disc has its state-specific colour, glyph, and legend', (
    tester,
  ) async {
    final cases = <PttState, ({Color color, String legend, IconData icon})>{
      PttState.idle: (
        color: KeryxTheme.lcd,
        legend: 'PTT',
        icon: Icons.mic_none_outlined,
      ),
      PttState.granted: (
        color: KeryxTheme.tx,
        legend: 'PTT',
        icon: Icons.mic_none_outlined,
      ),
      PttState.receiving: (
        color: KeryxTheme.rx,
        legend: 'BUSY',
        icon: Icons.volume_up_outlined,
      ),
      PttState.emergency: (
        color: KeryxTheme.emergency,
        legend: 'CANCEL',
        icon: Icons.mic_none_outlined,
      ),
    };
    final controller = PttRingController();
    addTearDown(controller.dispose);

    for (final entry in cases.entries) {
      await tester.pumpWidget(_disc(entry.key, controller));
      await tester.pump();
      expect(find.text(entry.value.legend), findsOneWidget);
      final icon = tester.widget<Icon>(
        find.byKey(const Key('keryx-ptt-glyph')),
      );
      expect(icon.icon, entry.value.icon);
      expect(icon.color, entry.value.color);
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const Key('keryx-ptt-surface')),
      );
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.border, isA<Border>());
      expect(
        (decoration.border! as Border).top.color,
        entry.value.color.withValues(alpha: .7),
      );
    }
  });

  testWidgets(
    'injected controller changes the reported number of lit ring ticks',
    (tester) async {
      final controller = PttRingController(0);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_disc(PttState.idle, controller));
      Finder meter(String label) => find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );
      expect(meter('Amplitude meter, 0 of 64 ticks'), findsOneWidget);

      controller.setLevel(75);
      await tester.pump();
      expect(meter('Amplitude meter, 48 of 64 ticks'), findsOneWidget);

      controller.setLevel(100);
      await tester.pump();
      expect(meter('Amplitude meter, 64 of 64 ticks'), findsOneWidget);
    },
  );

  testWidgets(
    'TX uses one-dp travel, drops raised edges, and gains inner shadow',
    (tester) async {
      final controller = PttRingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_disc(PttState.granted, controller));
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const Key('keryx-ptt-surface')),
      );
      expect(surface.transform!.getTranslation().y, KeryxTheme.keyTravel);
      final decoration = surface.decoration! as BoxDecoration;
      expect(decoration.boxShadow!.single.blurStyle, BlurStyle.inner);
    },
  );

  testWidgets('press and release keep the existing floor callbacks', (
    tester,
  ) async {
    final controller = PttRingController();
    addTearDown(controller.dispose);
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PttButton(
            state: PttState.idle,
            ringController: controller,
            onPressStart: () => events.add('down'),
            onPressEnd: () => events.add('up'),
            onLatchToggled: (_) {},
            onGrantHaptic: () async {},
            onDeniedHaptic: () async {},
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('keryx-ptt-disc'))),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(events, <String>['down', 'up']);
  });

  testWidgets('key rail remains below the hero disc', (tester) async {
    final controller = PttRingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PttButton(
                state: PttState.idle,
                ringController: controller,
                onPressStart: () {},
                onPressEnd: () {},
                onLatchToggled: (_) {},
              ),
              PttKeyRow(
                onMonHoldStart: () {},
                onMonHoldEnd: () {},
                onScan: () {},
                onSayAgain: () {},
                onSettings: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('MON'), findsOneWidget);
    expect(find.text('SCAN'), findsOneWidget);
    expect(find.text('STN'), findsOneWidget);
    expect(find.text('EMG'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const Key('keryx-ptt-key-mon'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const Key('keryx-ptt-disc'))).dy,
      ),
    );
  });
}
