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
import 'package:keryx/services/session/session.dart' show StationInfo;

import 'fake_radio_host.dart';

/// A silent, single-device [FloorTransport] — enough to satisfy
/// [FloorEngine]'s constructor without touching a real transport. This
/// file's own from-scratch equivalent of the pattern
/// `test/core/radio_host/keryx_radio_host_test.dart` documents (that class
/// is private to its own file).
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
  late FakeRadioHost host;
  late ProviderContainer container;

  Widget build({FakeRadioHost? withHost}) {
    host = withHost ?? host;
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
        home: TalkScreen(host: host),
      ),
    );
  }

  setUp(() {
    host = FakeRadioHost();
  });

  // `FloorEngine` arms a real (fake-clock) presence-heartbeat timer on
  // construction. Only its identity/non-null-ness matters to this screen
  // (Design/Technical never route a Talk-screen gesture through it
  // directly — every PTT action goes through `RadioHost`), so every engine
  // built for a test is disposed immediately after it has served its one
  // purpose (arming `RadioHostSnapshot.floorEngine`) rather than kept
  // "live" for the rest of the test — `addTearDown` fires too late to
  // satisfy `flutter_test`'s pending-timer invariant, which runs before
  // the zone-level teardown queue.
  Future<void> pumpReady(WidgetTester tester, {FloorEngine? engine}) async {
    final FloorEngine resolved = engine ?? _newEngine();
    host.emit(RadioHostSnapshot(floorEngine: resolved));
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted());
    await tester.pumpAndSettle();
    resolved.dispose();
  }

  group('VT-011 — request/grant/release', () {
    testWidgets(
      'pointer-down creates exactly one request; before grant there is no '
      'red TX; release sends exactly one release intent',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpReady(tester);

        expect(host.pressPttCalls, 0);
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
        );
        await tester.pump();
        expect(host.pressPttCalls, 1);
        expect(host.releasePttCalls, 0);
        // Not yet granted — the disc must not render the TX toggled state.
        final Semantics discSemantics = tester.widget<Semantics>(
          find.byKey(const Key('keryx-talk-ptt-disc-semantics')),
        );
        expect(discSemantics.properties.toggled, isNot(true));

        await gesture.up();
        await tester.pumpAndSettle();
        expect(host.releasePttCalls, 1);
        handle.dispose();
      },
    );

    testWidgets(
      'a second, overlapping pointer on the disc causes no duplicate or '
      'stuck transmission (VT-011)',
      (tester) async {
        await pumpReady(tester);
        final center = tester.getCenter(
          find.byKey(const Key('keryx-talk-ptt-disc')),
        );
        // Two genuinely distinct pointer identities, both routed by the
        // real `GestureBinding` (unlike a synthetic same-pointer replay,
        // which the framework itself would refuse to route a second time)
        // — the realistic shape of "duplicate" this widget must guard
        // against: an accidental second finger on the same disc while the
        // first hold is still down.
        final firstFinger = await tester.startGesture(
          center,
          pointer: 1,
        );
        await tester.pump();
        expect(host.pressPttCalls, 1);

        final secondFinger = await tester.startGesture(
          center,
          pointer: 2,
        );
        await tester.pump();
        // The overlapping second pointer-down must not issue a second
        // request.
        expect(host.pressPttCalls, 1);

        await firstFinger.up();
        await tester.pump();
        expect(host.releasePttCalls, 1);

        await secondFinger.up();
        await tester.pump();
        // The second finger's up, arriving after the hold was already
        // released, must not send a second, stuck-looking release.
        expect(host.releasePttCalls, 1);
        expect(host.pressPttCalls, 1);
      },
    );

    testWidgets('a late grant after release causes no duplicate transmission', (
      tester,
    ) async {
      await pumpReady(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(host.releasePttCalls, 1);

      // The "late grant" — an asynchronous RadioState transition arriving
      // after the UI already released — must only ever repaint, never
      // issue another host call.
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted());
      await tester.pumpAndSettle();
      expect(host.pressPttCalls, 1);
      expect(host.releasePttCalls, 1);
    });
  });

  group('VT-012 — cancellation and disposal', () {
    testWidgets('pointer cancellation releases an ordinary hold safely', (
      tester,
    ) async {
      await pumpReady(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      expect(host.releasePttCalls, 1);
    });

    testWidgets('route unmount during a hold releases it and creates no '
        'latch', (tester) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      expect(host.pressPttCalls, 1);
      expect(host.releasePttCalls, 0);

      // Unmount the whole tree — mirrors a route pop mid-hold.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(host.releasePttCalls, 1);
      expect(host.releaseLatchCalls, 0);
    });

    testWidgets('permission loss mid-hold releases it safely', (
      tester,
    ) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      expect(host.pressPttCalls, 1);

      host.emit(
        RadioHostSnapshot(
          floorEngine: host.current.floorEngine,
          micPermissionDenied: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(host.releasePttCalls, 1);
    });

    testWidgets('engine replacement mid-hold releases it safely', (
      tester,
    ) async {
      final firstEngine = _newEngine();
      await pumpReady(tester, engine: firstEngine);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      expect(host.pressPttCalls, 1);

      final secondEngine = _newEngine(peerId: 'other');
      host.emit(RadioHostSnapshot(floorEngine: secondEngine));
      await tester.pumpAndSettle();
      secondEngine.dispose();
      expect(host.releasePttCalls, 1);
    });

    testWidgets(
      'a deliberate latch is not released by route unmount (Technical §4)',
      (tester) async {
        await pumpReady(tester);
        await tester.startGesture(
          tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
        );
        await tester.pump();
        container.read(radioStateProvider.notifier)
          ..dispatch(const PowerOn())
          ..dispatch(const BootCompleted())
          ..dispatch(const RequestTransmit())
          ..dispatch(const TransmitGranted());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('keryx-talk-latch')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('keryx-talk-unlatch')), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        // Latching means the ordinary release was never sent, and
        // unmounting a latched hold must not synthesize one either.
        expect(host.releasePttCalls, 0);
        expect(host.releaseLatchCalls, 0);
      },
    );
  });

  group('latch — explicit affordance (Technical §5.2 replacement rationale)', () {
    testWidgets('engaging latch then releasing calls releaseLatch exactly '
        'once', (tester) async {
      await pumpReady(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('keryx-talk-latch')));
      await tester.pumpAndSettle();

      await gesture.up();
      await tester.pumpAndSettle();
      // Latched: the physical release must NOT end the floor.
      expect(host.releasePttCalls, 0);

      await tester.tap(find.byKey(const Key('keryx-talk-unlatch')));
      await tester.pumpAndSettle();
      expect(host.releaseLatchCalls, 1);
      expect(find.byKey(const Key('keryx-talk-latch')), findsOneWidget);
    });

    testWidgets('the latch control is unavailable before a real grant', (
      tester,
    ) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      // Still only txRequest — never actually granted.
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('keryx-talk-latch')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('non-drag accessible alternative', () {
    testWidgets('toggle alternative starts and stops a hold without a '
        'sustained pointer', (tester) async {
      await pumpReady(tester);
      expect(find.text('Start transmitting'), findsOneWidget);

      await tester.tap(find.byKey(const Key('keryx-talk-ptt-toggle-alt')));
      await tester.pump();
      expect(host.pressPttCalls, 1);
      expect(find.text('Stop transmitting'), findsOneWidget);

      await tester.tap(find.byKey(const Key('keryx-talk-ptt-toggle-alt')));
      await tester.pump();
      expect(host.releasePttCalls, 1);
      expect(find.text('Start transmitting'), findsOneWidget);
    });
  });

  group('VT-010 — state matrix', () {
    testWidgets('a pending request never renders as granted TX', (
      tester,
    ) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      // A real `RadioHost.pressPtt()` forwards to `FloorEngine
      // .requestTransmit`, whose grant/deny effect the bridge dispatches
      // back as `RequestTransmit` — reproduced explicitly here since
      // `FakeRadioHost.pressPtt` intentionally does not reduce state itself
      // (Technical §5.1: the UI/host boundary never synthesizes a result).
      container.read(radioStateProvider.notifier).dispatch(
        const RequestTransmit(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Requesting channel…'), findsWidgets);
      expect(find.text('Transmitting'), findsNothing);
    });

    testWidgets('receiving shows the resolved callsign, never the raw '
        'peer ID', (tester) async {
      await pumpReady(tester);
      host.emit(
        RadioHostSnapshot(
          floorEngine: host.current.floorEngine,
          stations: const <StationInfo>[
            StationInfo(peerId: 'peer-77', callsign: 'ALPHA-1'),
          ],
        ),
      );
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const RemoteFloorStarted())
        ..dispatch(const ActiveSpeakerChanged('peer-77'));
      await tester.pumpAndSettle();
      expect(find.text('ALPHA-1 speaking'), findsWidgets);
      expect(find.text('peer-77'), findsNothing);
    });

    testWidgets('unresolved speaker falls back to a neutral label, never '
        'the raw peer ID', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const RemoteFloorStarted())
        ..dispatch(const ActiveSpeakerChanged('peer-unknown'));
      await tester.pumpAndSettle();
      expect(find.text('Someone is speaking'), findsWidgets);
      expect(find.text('peer-unknown'), findsNothing);
    });

    testWidgets('a disconnected screen never shows the idle "Ready" copy', (
      tester,
    ) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const LinkDegraded());
      await tester.pumpAndSettle();
      expect(find.text('Connection lost'), findsWidgets);
      expect(find.text('Hold to talk'), findsNothing);
    });

    testWidgets('emergency renders as an independent overlay, never hidden '
        'behind or by the ordinary floor phase (Design §4)', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const EmergencyPinned());
      await tester.pumpAndSettle();
      expect(find.text('Emergency active'), findsOneWidget);
      // Ordinary PTT is still its own, separate control underneath.
      expect(find.byKey(const Key('keryx-talk-ptt-disc')), findsOneWidget);
    });

    testWidgets('a denied/busy flash never overrides a currently granted '
        'TX (Design §4)', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted())
        ..dispatch(const TransmitDeniedIndicated());
      await tester.pumpAndSettle();
      // Both are independently true and both are rendered — the granted
      // TX is not concealed by the transient deny overlay.
      expect(find.text('Channel busy'), findsOneWidget);
      expect(find.text('Transmitting'), findsWidgets);
    });

    testWidgets('the radio-off state disables the PTT surface', (
      tester,
    ) async {
      final engine = _newEngine();
      host.emit(RadioHostSnapshot(floorEngine: engine));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      engine.dispose();
      // No PowerOn dispatched — phase stays RadioPhase.off.
      expect(find.text('Radio off'), findsWidgets);
      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('keryx-talk-ptt-toggle-alt')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'lacking a usable floor engine disables the PTT surface (UX-FR-029)',
      (tester) async {
        host.emit(const RadioHostSnapshot());
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        container.read(radioStateProvider.notifier)
          ..dispatch(const PowerOn())
          ..dispatch(const BootCompleted());
        await tester.pumpAndSettle();
        final button = tester.widget<OutlinedButton>(
          find.descendant(
            of: find.byKey(const Key('keryx-talk-ptt-toggle-alt')),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('permission-denied disables the PTT surface and shows the '
        'persistent overlay message', (tester) async {
      host.emit(
        const RadioHostSnapshot(micPermissionDenied: true),
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.text('Microphone required'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.descendant(
          of: find.byKey(const Key('keryx-talk-ptt-toggle-alt')),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('VT-015 — audio truthfulness', () {
    testWidgets('no signal-quality or roster count is presented as a '
        'verified value when unavailable', (tester) async {
      await pumpReady(tester);
      // LOCAL is the default `RadioState.mode`; roster is verified for
      // LOCAL, so drive an unavailable case via a LINKED effective route.
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const SetMode(RadioMode.linked));
      await tester.pumpAndSettle();
      expect(find.text('Member list unavailable'), findsOneWidget);
    });
  });

  group('sizing', () {
    testWidgets('the PTT disc meets the 96 dp minimum primary dimension', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      await pumpReady(tester);
      final size = tester.getSize(
        find.byKey(const Key('keryx-talk-ptt-disc')),
      );
      expect(size.width, greaterThanOrEqualTo(96));
      expect(size.height, greaterThanOrEqualTo(96));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    testWidgets('content is visible at 320 logical-pixel width without '
        'overflow', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      await pumpReady(tester);
      expect(tester.takeException(), isNull);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}
