import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/ptt/ptt_button.dart';
import 'package:keryx/features/ptt/ptt_state.dart';

/// Host harness: round-trips PttButton's callbacks into a local `PttState`,
/// same pattern as `test/features/knob/keryx_tuning_knob_test.dart`'s
/// `_Harness`.
class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    this.latchEnabled = false,
    this.initialState = PttState.idle,
  });

  final bool latchEnabled;
  final PttState initialState;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late PttState _state = widget.initialState;
  final List<String> events = <String>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: PttButton(
            state: _state,
            latchEnabled: widget.latchEnabled,
            onGrantHaptic: () async {},
            onDeniedHaptic: () async {},
            onPressStart: () {
              events.add('pressStart');
              setState(() => _state = PttState.granted);
            },
            onPressEnd: () {
              events.add('pressEnd');
              setState(() => _state = PttState.idle);
            },
            onLatchToggled: (locked) {
              events.add(locked ? 'latchOn' : 'latchOff');
              setState(() => _state = locked ? PttState.latched : PttState.idle);
            },
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('press-and-release fires onPressStart then onPressEnd', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.pump();

    final surface = find.byKey(const Key('keryx-ptt-surface'));
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await tester.pump();
    expect(key.currentState!.events, <String>['pressStart']);

    await gesture.up();
    await tester.pump();
    expect(key.currentState!.events, <String>['pressStart', 'pressEnd']);
  });

  testWidgets('red (KeryxTheme.tx-family gradient) only renders when granted', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(initialState: PttState.idle));
    await tester.pump();

    Container surfaceContainer() => tester.widget<Container>(
      find
          .descendant(
            of: find.byKey(const Key('keryx-ptt-surface')),
            matching: find.byType(Container),
          )
          .first,
    );

    BoxDecoration idleDecoration() =>
        surfaceContainer().decoration! as BoxDecoration;
    final idleGradient = idleDecoration().gradient! as LinearGradient;
    // Idle must not use the granted (red-family) gradient.
    expect(idleGradient.colors, isNot(contains(const Color(0xFF5A1D18))));

    // A fresh key forces a new State (rather than an update of the existing
    // one), since `_state` is seeded from `initialState` only in `initState`.
    await tester.pumpWidget(
      _Harness(key: UniqueKey(), initialState: PttState.granted),
    );
    await tester.pump();
    final grantedGradient =
        surfaceContainer().decoration! as BoxDecoration;
    final grantedColors = (grantedGradient.gradient! as LinearGradient).colors;
    expect(grantedColors, contains(const Color(0xFF5A1D18)));
  });

  testWidgets('denied state shows the deny flash for ~260ms then clears', (
    tester,
  ) async {
    final harnessKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PttButton(
              key: harnessKey,
              state: PttState.idle,
              onGrantHaptic: () async {},
              onDeniedHaptic: () async {},
              onPressStart: () {},
              onPressEnd: () {},
              onLatchToggled: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final buttonState =
        tester.state<PttButtonState>(find.byKey(harnessKey));
    expect(buttonState.isShowingDenyFlash, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PttButton(
              key: harnessKey,
              state: PttState.denied,
              onGrantHaptic: () async {},
              onDeniedHaptic: () async {},
              onPressStart: () {},
              onPressEnd: () {},
              onLatchToggled: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(buttonState.isShowingDenyFlash, isTrue);

    await tester.pump(const Duration(milliseconds: 260));
    expect(buttonState.isShowingDenyFlash, isFalse);
  });

  testWidgets('latch: double-tap engages latch, tap while latched releases', (
    tester,
  ) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key, latchEnabled: true));
    await tester.pump();

    final surface = find.byKey(const Key('keryx-ptt-surface'));
    final center = tester.getCenter(surface);

    // First tap: normal hold-to-talk press/release.
    var gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(key.currentState!.events, <String>['pressStart', 'pressEnd']);

    // Second tap, quickly after: engages latch instead.
    key.currentState!.events.clear();
    gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(key.currentState!.events, <String>['latchOn']);
    expect(key.currentState!.mounted, isTrue);

    // Now latched: any tap releases.
    key.currentState!.events.clear();
    gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(key.currentState!.events, <String>['latchOff']);
  });

  testWidgets('pressed state applies KeryxTheme.keyTravel translation', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness(initialState: PttState.granted));
    await tester.pump();

    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const Key('keryx-ptt-surface')),
    );
    final transform = surface.transform!;
    expect(transform.getTranslation().y, KeryxTheme.keyTravel);
  });

  testWidgets('disabled PttButton ignores gestures', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PttButton(
              state: PttState.idle,
              enabled: false,
              onGrantHaptic: () async {},
              onDeniedHaptic: () async {},
              onPressStart: () => events.add('pressStart'),
              onPressEnd: () => events.add('pressEnd'),
              onLatchToggled: (_) => events.add('latch'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surface = find.byKey(const Key('keryx-ptt-surface'));
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(events, isEmpty);
  });
}
