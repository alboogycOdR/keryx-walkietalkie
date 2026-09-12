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
import 'package:keryx/core/presentation/telemetry.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/talk/talk_screen.dart';

import '../../features/talk/fake_radio_host.dart';

/// v2 (TASK-092): every state golden below exercises a reachable target
/// (mirrors `talk_screen_test.dart`'s `_defaultTestTarget`) so the existing
/// v1-equivalent ring states keep rendering the ring, not the no-target
/// card. Dedicated goldens further down cover the no-target and
/// nobody-listening states explicitly.
const _defaultGoldenTarget = TalkTarget(
  kind: TalkTargetKind.contact,
  id: 'peer-1',
  name: 'Ben',
  roomId: 'room-1',
  memberPeerIds: ['peer-1'],
);
const _defaultGoldenPresence = <String, PeerPresence>{
  'peer-1': PeerPresence.online,
};

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
    TalkTarget? target = _defaultGoldenTarget,
    Map<String, PeerPresence> presenceByPeerId = _defaultGoldenPresence,
    TalkAlert? pendingAlert,
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
          home: TalkScreen(
            host: host,
            target: target,
            presenceByPeerId: presenceByPeerId,
            pendingAlert: pendingAlert,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted());
    await tester.pumpAndSettle();

    arrange(host, container, engine);
    // Some ring treatments (requesting's sweep) animate continuously by
    // design (ADR-002 A3), so `pumpAndSettle` never settles here — pump a
    // bounded number of frames instead, enough for one-shot transitions
    // (denied shake, press scale) to finish.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

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

    testWidgets('Talk — receiving with measured glow ($suffix)', (
      tester,
    ) async {
      await pumpAndGolden(
        tester,
        name: 'receiving_glow_$suffix',
        brightness: brightness,
        arrange: (host, container, engine) {
          container.read(radioStateProvider.notifier).dispatch(
                const RemoteFloorStarted(),
              );
          host.emit(
            RadioHostSnapshot(
              floorEngine: engine,
              meterLevel: const MeasuredMeterLevel(80),
            ),
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

    // v2 (TASK-092, Design §2.1/§4).
    testWidgets('Talk — no target ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'no_target_$suffix',
        brightness: brightness,
        target: null,
        arrange: (host, container, engine) {},
      );
    });

    testWidgets('Talk — nobody listening ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'nobody_listening_$suffix',
        brightness: brightness,
        presenceByPeerId: const {'peer-1': PeerPresence.offline},
        arrange: (host, container, engine) {},
      );
    });

    testWidgets('Talk — alert received banner ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'alert_banner_$suffix',
        brightness: brightness,
        pendingAlert: TalkAlert(
          senderLabel: 'BEN·4R2M',
          receivedAt: DateTime(2026),
        ),
        arrange: (host, container, engine) {},
      );
    });
  }
}
