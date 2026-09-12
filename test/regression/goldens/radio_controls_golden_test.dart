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
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';

import '../../app_shell/fake_radio_host.dart';

/// Silent single-device transport — same shape as
/// `test/features/radio_controls/radio_controls_screen_test.dart`'s
/// `_NullFloorTransport`, needed only so a real [FloorEngine] can be
/// attached (this task's territory has no production file to reuse a test
/// helper class from across a feature-test directory boundary for this).
class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void dispose() => unawaited(_incoming.close());
}

/// TASK-058 — Verification §6: golden fixture for Radio Controls, dark and
/// light.
void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = FakeRadioHost();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: RadioControlsScreen(host: host))));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(RadioControlsScreen),
      matchesGoldenFile('goldens/radio_controls_$name.png'));
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('Radio Controls ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: suffix, brightness: brightness);
    });
  }

  // REWORK round 1 finding (3): TASK-069's own approval routed "TASK-058
  // should assert these sizes explicitly" — `androidTapTargetGuideline`
  // structurally cannot see the Monitor/Emergency hold targets' 48 dp size
  // because their `Semantics` wrapper is non-container and its tap action
  // merges into a larger ancestor node. Measure the render boxes directly
  // instead, which routes around that blind spot.
  testWidgets(
    'Monitor and Emergency hold targets each meet the 48 dp minimum '
    '(TASK-069 finding, closed by TASK-058)',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final host = FakeRadioHost();
      final transport = _NullFloorTransport();
      final engine = FloorEngine(
        localPeerId: 'local',
        transport: transport,
        clock: const WallClock(),
        tot: const Duration(seconds: 60));
      // Both Monitor and Emergency need `RadioHostSnapshot.floorEngine` set
      // (Monitor for `_eligible`'s idle-phase requirement, Emergency because
      // its hold target is swapped for an "unavailable" explanation entirely
      // when no engine is attached) and the radio phase must reach `idle`
      // for Monitor's own eligibility gate — matches
      // `radio_controls_screen_test.dart`'s own `pumpReady` pattern.
      host.emit(RadioHostSnapshot(floorEngine: engine));

      final container = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: keryxUxThemeData(brightness: Brightness.dark),
            home: RadioControlsScreen(host: host))));
      await tester.pumpAndSettle();
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted());
      await tester.pumpAndSettle();

      // The screen lays its content out in a `ListView`; the Emergency row
      // sits below the Monitor row and can fall outside the initial build
      // extent, so scroll each target into view before measuring it.
      await tester.ensureVisible(
        find.byKey(RadioControlsKeys.monitorHoldTarget));
      await tester.pumpAndSettle();
      final Size monitorSize = tester.getSize(
        find.byKey(RadioControlsKeys.monitorHoldTarget));

      await tester.ensureVisible(
        find.byKey(RadioControlsKeys.emergencyHoldTarget));
      await tester.pumpAndSettle();
      final Size emergencySize = tester.getSize(
        find.byKey(RadioControlsKeys.emergencyHoldTarget));

      expect(monitorSize.width, greaterThanOrEqualTo(KeryxUxSpacing.minTarget));
      expect(
        monitorSize.height,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget));
      expect(
        emergencySize.width,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget));
      expect(
        emergencySize.height,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget));

      engine.dispose();
      transport.dispose();
    });
}
