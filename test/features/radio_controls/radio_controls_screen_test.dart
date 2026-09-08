import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/radio_controls/radio_controls_copy.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';

import 'fake_radio_host.dart';

/// A silent, single-device [FloorTransport] that can also be fed an inbound
/// message directly — matches the pattern
/// `test/features/talk/talk_screen_test.dart` documents, extended with a
/// [deliver] helper so a test can simulate a remote peer's `EMG` pin.
class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void deliver(FloorMessage message) => _incoming.add(message);

  void dispose() => unawaited(_incoming.close());
}

(FloorEngine, _NullFloorTransport) _newEngine({String peerId = 'local'}) {
  final transport = _NullFloorTransport();
  final engine = FloorEngine(
    localPeerId: peerId,
    transport: transport,
    clock: const WallClock(),
    tot: const Duration(seconds: 60),
  );
  return (engine, transport);
}

void main() {
  late FakeRadioHost host;
  late ProviderContainer container;

  Widget build() {
    container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: keryxUxThemeData(),
        home: RadioControlsScreen(host: host),
      ),
    );
  }

  setUp(() {
    host = FakeRadioHost();
  });

  /// Boots the radio to `idle` (the eligible phase for Monitor/Scan) with a
  /// real [FloorEngine] attached — same reasoning as
  /// `talk_screen_test.dart`'s `pumpReady`: the engine only needs to exist
  /// and be disposed at the end, no live session behind it.
  Future<FloorEngine> pumpReady(WidgetTester tester, {FloorEngine? engine}) async {
    final FloorEngine resolved = engine ?? _newEngine().$1;
    host.emit(RadioHostSnapshot(floorEngine: resolved));
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted());
    await tester.pumpAndSettle();
    return resolved;
  }

  group('acceptance criterion 1 — only implemented rows appear', () {
    testWidgets(
      'Monitor, Scan and Emergency render; Latch/VOX/Replay are absent, '
      'not faked',
      (tester) async {
        final engine = await pumpReady(tester);
        expect(find.text(RadioControlsCopy.monitorLabel), findsOneWidget);
        expect(find.text(RadioControlsCopy.scanLabel), findsOneWidget);
        // "Emergency" appears twice by design — the section title and the
        // idle hold-to-arm button's own label.
        expect(find.text(RadioControlsCopy.emergencyLabel), findsNWidgets(2));
        expect(find.textContaining('Latch'), findsNothing);
        expect(find.textContaining('VOX'), findsNothing);
        expect(find.textContaining('Replay'), findsNothing);
        engine.dispose();
      },
    );
  });

  group('acceptance criterion 2/4 — Monitor hold-to-open, authoritative state', () {
    testWidgets(
      'holding Monitor opens it (indicator lights); releasing closes it',
      (tester) async {
        final engine = await pumpReady(tester);
        expect(
          container.read(radioStateProvider).isMonitorOpen,
          isFalse,
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(RadioControlsKeys.monitorHoldTarget)),
        );
        await tester.pump();
        expect(container.read(radioStateProvider).isMonitorOpen, isTrue);

        await gesture.up();
        await tester.pump();
        expect(container.read(radioStateProvider).isMonitorOpen, isFalse);
        engine.dispose();
      },
    );

    testWidgets(
      'the indicator lights from authoritative state directly, not from a '
      'local tap alone — driving state without any gesture still lights it',
      (tester) async {
        final engine = await pumpReady(tester);
        // No gesture at all — dispatch straight to the reducer, exactly as
        // a real authoritative source would.
        container.read(radioStateProvider.notifier).dispatch(
          const MonitorChanged(true),
        );
        await tester.pump();

        final Icon indicator = tester.widget<Icon>(
          find.byKey(RadioControlsKeys.monitorIndicator),
        );
        final tokens = KeryxUxTokens.of(
          tester.element(find.byKey(RadioControlsKeys.monitorIndicator)),
        );
        expect(indicator.color, tokens.stateRx);
        engine.dispose();
      },
    );

    testWidgets(
      'Monitor is ineligible and explains itself while transmitting; the '
      'hold gesture is a no-op',
      (tester) async {
        final engine = await pumpReady(tester);
        container.read(radioStateProvider.notifier)
          ..dispatch(const RequestTransmit())
          ..dispatch(const TransmitGranted());
        await tester.pumpAndSettle();

        expect(find.byKey(RadioControlsKeys.monitorUnavailable), findsOneWidget);

        await tester.startGesture(
          tester.getCenter(find.byKey(RadioControlsKeys.monitorHoldTarget)),
        );
        await tester.pump();
        expect(container.read(radioStateProvider).isMonitorOpen, isFalse);
        engine.dispose();
      },
    );
  });

  group('acceptance criterion 2/4 — Scan toggle, authoritative state', () {
    testWidgets('tapping Scan toggles it on and off', (tester) async {
      final engine = await pumpReady(tester);
      expect(container.read(radioStateProvider).isScanning, isFalse);

      await tester.tap(find.byKey(RadioControlsKeys.scanSwitch));
      await tester.pump();
      expect(container.read(radioStateProvider).isScanning, isTrue);

      await tester.tap(find.byKey(RadioControlsKeys.scanSwitch));
      await tester.pump();
      expect(container.read(radioStateProvider).isScanning, isFalse);
      engine.dispose();
    });

    testWidgets(
      'Scan is ineligible and explains itself while transmitting; tapping '
      'is a no-op',
      (tester) async {
        final engine = await pumpReady(tester);
        container.read(radioStateProvider.notifier)
          ..dispatch(const RequestTransmit())
          ..dispatch(const TransmitGranted());
        await tester.pumpAndSettle();

        expect(find.byKey(RadioControlsKeys.scanUnavailable), findsOneWidget);

        await tester.tap(find.byKey(RadioControlsKeys.scanSwitch), warnIfMissed: false);
        await tester.pump();
        expect(container.read(radioStateProvider).isScanning, isFalse);
        engine.dispose();
      },
    );
  });

  group('acceptance criteria 5/6/7 — Emergency guarded activation and clear', () {
    testWidgets(
      'holding Emergency for the full 600ms arm duration activates it '
      'through the authoritative engine and shows the active banner',
      (tester) async {
        final engine = await pumpReady(tester);
        expect(engine.isEmergencyPinned, isFalse);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(RadioControlsKeys.emergencyHoldTarget)),
        );
        await tester.pump();
        expect(find.byKey(RadioControlsKeys.emergencyArming), findsOneWidget);
        expect(engine.isEmergencyPinned, isFalse);

        await tester.pump(const Duration(milliseconds: 650));
        expect(engine.isEmergencyPinned, isTrue);
        expect(find.byKey(RadioControlsKeys.emergencyBanner), findsOneWidget);

        await gesture.up();
        await tester.pump();
        engine.dispose();
      },
    );

    testWidgets(
      'releasing Emergency before the hold duration elapses does not '
      'activate it (accidental initiation prevented)',
      (tester) async {
        final engine = await pumpReady(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(RadioControlsKeys.emergencyHoldTarget)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 500));

        expect(engine.isEmergencyPinned, isFalse);
        expect(find.byKey(RadioControlsKeys.emergencyBanner), findsNothing);
        engine.dispose();
      },
    );

    testWidgets(
      'the owner can clear an active emergency through the authoritative '
      'engine; the banner disappears',
      (tester) async {
        final engine = await pumpReady(tester);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(RadioControlsKeys.emergencyHoldTarget)),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await gesture.up();
        await tester.pump();
        expect(engine.isEmergencyPinned, isTrue);

        await tester.tap(find.byKey(RadioControlsKeys.emergencyClear));
        await tester.pump();

        expect(engine.isEmergencyPinned, isFalse);
        expect(find.byKey(RadioControlsKeys.emergencyBanner), findsNothing);
        engine.dispose();
      },
    );

    testWidgets(
      'a non-owner cannot clear a remotely-raised emergency — the clear '
      'action is disabled and the reason is explained',
      (tester) async {
        final (engine, transport) = _newEngine();
        await pumpReady(tester, engine: engine);
        // Remote peer pins emergency over the wire (mirrors an incoming
        // EMG protocol message) — never a widget-local mutation.
        transport.deliver(const Emg(peer: 'remote-1'));
        await tester.pump();
        await tester.pump();

        expect(engine.isEmergencyPinned, isTrue);
        expect(engine.emergencyPeer, 'remote-1');
        expect(
          find.byKey(RadioControlsKeys.emergencyClearedByOther),
          findsOneWidget,
        );

        final FilledButton clearButton = tester.widget<FilledButton>(
          find.byKey(RadioControlsKeys.emergencyClear),
        );
        expect(clearButton.onPressed, isNull);
        engine.dispose();
        transport.dispose();
      },
    );

    testWidgets(
      'no location or emergency-service claim appears in the emergency copy',
      (tester) async {
        final engine = await pumpReady(tester);
        expect(find.textContaining('location'), findsOneWidget);
        expect(
          find.text(RadioControlsCopy.emergencyDescription),
          findsOneWidget,
        );
        expect(find.textContaining('911'), findsNothing);
        expect(find.textContaining('emergency service'), findsOneWidget);
        engine.dispose();
      },
    );
  });
}
