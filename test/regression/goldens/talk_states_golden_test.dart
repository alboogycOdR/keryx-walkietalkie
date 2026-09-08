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
import 'package:keryx/features/talk/talk_screen.dart';

import '../../features/talk/fake_radio_host.dart';

/// TASK-058 — Verification §6: "Create golden fixtures for every
/// significant Talk state... Cover dark and light themes."
///
/// A silent, single-device [FloorTransport] — this file's own from-scratch
/// equivalent of the pattern already used by
/// `test/core/radio_host/keryx_radio_host_test.dart` and
/// `test/features/talk/talk_screen_test.dart` (both files' own versions are
/// private, so this is a fresh copy under this task's `Owned_Paths`, not a
/// cross-file import of a private class).
class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void dispose() => unawaited(_incoming.close());
}

FloorEngine _newEngine({String peerId = 'local'}) => FloorEngine(
      localPeerId: peerId,
      transport: _NullFloorTransport(),
      clock: const WallClock(),
      tot: const Duration(seconds: 60),
    );

void main() {
  /// Pumps [TalkScreen] in a fixed phone-sized surface with the given
  /// theme, drives `radioStateProvider` to [phase] via real reducer events
  /// (never a hand-constructed `RadioState`, so every golden reflects a
  /// state the reducer actually produces), then captures a golden.
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required void Function(
      FakeRadioHost host,
      ProviderContainer container,
      FloorEngine engine,
    )
        arrange,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = FakeRadioHost();
    final engine = _newEngine();
    host.emit(RadioHostSnapshot(floorEngine: engine));
    final container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: TalkScreen(host: host),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted());
    await tester.pumpAndSettle();

    arrange(host, container, engine);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TalkScreen),
      matchesGoldenFile('goldens/talk_$name.png'),
    );

    engine.dispose();
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Talk — idle ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'idle_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {},
      );
    });

    testWidgets('Talk — requesting ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'requesting_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          container.read(radioStateProvider.notifier).dispatch(
                const RequestTransmit(),
              );
        },
      );
    });

    testWidgets('Talk — granted / transmitting ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'granted_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          container.read(radioStateProvider.notifier)
            ..dispatch(const RequestTransmit())
            ..dispatch(const TransmitGranted());
        },
      );
    });

    testWidgets('Talk — receiving ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'receiving_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          container.read(radioStateProvider.notifier).dispatch(
                const RemoteFloorStarted(),
              );
        },
      );
    });

    testWidgets('Talk — degraded link ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'degraded_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          container.read(radioStateProvider.notifier).dispatch(
                const LinkDegraded(),
              );
        },
      );
    });

    testWidgets('Talk — emergency ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'emergency_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          container.read(radioStateProvider.notifier).dispatch(
                const EmergencyPinned(),
              );
        },
      );
    });

    testWidgets('Talk — permission denied ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'permission_denied_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          host.emit(
            RadioHostSnapshot(floorEngine: engine, micPermissionDenied: true),
          );
        },
      );
    });

    testWidgets('Talk — service fault ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'service_fault_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          host.emit(
            RadioHostSnapshot(
              floorEngine: engine,
              serviceFaultMessage: 'SVC FAULT',
            ),
          );
        },
      );
    });
  }
}
