import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/talk/talk_copy.dart';
import 'package:keryx/features/talk/talk_ptt_ring.dart';
import 'package:keryx/features/talk/talk_screen.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

import 'a11y_matrix_support.dart';
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

  Widget build({
    FakeRadioHost? withHost,
    Brightness brightness = Brightness.dark,
    VoidCallback? onOpenPicker,
    VoidCallback? onOpenStations,
    VoidCallback? onOpenRadioControls,
    Widget Function(Widget talkScreen)? wrapHome,
  }) {
    host = withHost ?? host;
    container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);
    final Widget talkScreen = TalkScreen(
      host: host,
      onOpenPicker: onOpenPicker,
      onOpenStations: onOpenStations,
      onOpenRadioControls: onOpenRadioControls,
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: wrapHome == null ? talkScreen : wrapHome(talkScreen),
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
  Future<void> pumpReady(
    WidgetTester tester, {
    FloorEngine? engine,
    Brightness brightness = Brightness.dark,
  }) async {
    final FloorEngine resolved = engine ?? _newEngine();
    host.emit(RadioHostSnapshot(floorEngine: resolved));
    await tester.pumpWidget(build(brightness: brightness));
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

    testWidgets(
      'a deliberate latch survives route unmount and remains releasable '
      'on remount (round-1 review BLOCKING 1/2)',
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

        // Unmount — mirrors a route pop while latched.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(host.releasePttCalls, 0);
        expect(host.releaseLatchCalls, 0);

        // Remount against the SAME persistent host and provider container
        // (mirrors navigating back to Talk in the real app, where
        // `RadioHost`/`ProviderContainer` are app-scoped and outlive the
        // route — `build()` would construct a brand-new container/settings
        // store, which is not what a real remount does). A widget-local
        // latch flag (round-1's defect) would reset to `false` here and
        // silently drop both the overlay cue and the release affordance
        // while the floor is still actually held.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: keryxUxThemeData(),
              home: TalkScreen(host: host),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Transmission locked'), findsWidgets);
        expect(find.byKey(const Key('keryx-talk-unlatch')), findsOneWidget);
        expect(find.byKey(const Key('keryx-talk-latch')), findsNothing);

        // And it must actually still work: exactly one releaseLatch call
        // fires, and the screen returns to the un-latched affordance.
        await tester.tap(find.byKey(const Key('keryx-talk-unlatch')));
        await tester.pumpAndSettle();
        expect(host.releaseLatchCalls, 1);
        // Remounted State is not holding, so Lock must not reappear even
        // while the reducer is still in TX (TASK-074 latch-after-lift).
        expect(find.byKey(const Key('keryx-talk-latch')), findsNothing);
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
      // Finger already lifted; Lock requires an in-progress hold.
      expect(find.byKey(const Key('keryx-talk-latch')), findsNothing);
    });

    testWidgets(
      'grant then lift then tap Lock in the same frame does not latch '
      '(TASK-074 carry; VT-010; ADR-002 A5)',
      (tester) async {
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
        expect(find.byKey(const Key('keryx-talk-latch')), findsOneWidget);

        await gesture.up();
        // Same frame: the previous build still has the Lock control.
        await tester.tap(find.byKey(const Key('keryx-talk-latch')));
        await tester.pumpAndSettle();

        expect(host.releasePttCalls, 1);
        expect(host.releaseLatchCalls, 0);
        expect(find.byKey(const Key('keryx-talk-unlatch')), findsNothing);
        expect(find.text('Transmission locked'), findsNothing);
        expect(find.byKey(const Key('keryx-talk-latch')), findsNothing);
        final TalkPttRing ring = tester.widget<TalkPttRing>(
          find.byType(TalkPttRing),
        );
        expect(ring.treatment, isNot(TalkPttRingTreatment.latched));
      },
    );

    testWidgets('the latch control is unavailable before a real grant', (
      tester,
    ) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      // Still only txRequest — never actually granted (ADR-002 A4: the lock
      // control is visible only while TX is granted, not merely disabled).
      expect(find.byKey(const Key('keryx-talk-latch')), findsNothing);
    });
  });

  group('non-drag accessible alternative (ADR-002 A4)', () {
    // The visible "Start transmitting" button is gone (A4) — the non-drag
    // alternative now lives on the ring's own semantics custom action and
    // keyboard (`Enter`/`Space`) toggle.
    FocusNode ringFocusNode(WidgetTester tester) => Focus.of(
      tester.element(find.byKey(const Key('keryx-talk-ptt-disc'))),
    );

    testWidgets('no visible "Start transmitting" button is rendered '
        '(ADR-002 A4)', (tester) async {
      await pumpReady(tester);
      expect(find.text('Start transmitting'), findsNothing);
      expect(find.byKey(const Key('keryx-talk-ptt-toggle-alt')), findsNothing);
    });

    testWidgets(
      'keyboard Enter/Space toggles a hold without a sustained pointer',
      (tester) async {
        await pumpReady(tester);
        ringFocusNode(tester).requestFocus();
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(host.pressPttCalls, 1);

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(host.releasePttCalls, 1);
      },
    );

    testWidgets(
      'the ring exposes a "Start transmitting"/"Stop transmitting" custom '
      'semantics action reachable by TalkBack (ADR-002 A4)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpReady(tester);
        final Semantics node = tester.widget<Semantics>(
          find.byKey(const Key('keryx-talk-ptt-disc-semantics')),
        );
        expect(
          node.properties.customSemanticsActions?.keys
              .map((CustomSemanticsAction a) => a.label),
          contains('Start transmitting'),
        );
        handle.dispose();
      },
    );
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
      // The requesting treatment's sweep animates continuously by design
      // (ADR-002 A3) — `pumpAndSettle` never settles here.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
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
      final TalkPttRing ring = tester.widget<TalkPttRing>(
        find.byType(TalkPttRing),
      );
      expect(ring.enabled, isFalse);
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
        final TalkPttRing ring = tester.widget<TalkPttRing>(
          find.byType(TalkPttRing),
        );
        expect(ring.enabled, isFalse);
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
      final TalkPttRing ring = tester.widget<TalkPttRing>(
        find.byType(TalkPttRing),
      );
      expect(ring.enabled, isFalse);
    });
  });

  group('ADR-002 A3 — ring treatment/colour per Design §4 row (one test per '
      'row)', () {
    // [TalkPttRing.treatment]/[TalkPttRing.ringColor] are the semantic
    // values `TalkScreen` computed and handed down — asserted on the widget
    // itself, not the rendered `CustomPaint`'s pixels, matching the
    // pre-ADR-002 disc tests' own rationale (round-1 review BLOCKING 3a):
    // the disc/ring's own disabled-state dimming is that widget's own
    // presentation concern, not part of what this screen is responsible for
    // choosing per Design §4's catalogue row.
    TalkPttRing ringWidget(WidgetTester tester) =>
        tester.widget<TalkPttRing>(find.byType(TalkPttRing));

    Icon overlayIcon(WidgetTester tester, String iconId) => tester.widget<Icon>(
      find.descendant(
        of: find.byKey(Key('keryx-talk-overlay-$iconId')),
        matching: find.byType(Icon),
      ),
    );

    testWidgets('Off: neutral treatment, PTT disabled', (tester) async {
      final engine = _newEngine();
      host.emit(RadioHostSnapshot(floorEngine: engine));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      engine.dispose();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.neutral);
      expect(ring.ringColor, tokens.pttNeutralRing);
      expect(ring.enabled, isFalse);
    });

    testWidgets('Boot: neutral treatment', (tester) async {
      final engine = _newEngine();
      host.emit(RadioHostSnapshot(floorEngine: engine));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      container.read(radioStateProvider.notifier).dispatch(const PowerOn());
      await tester.pumpAndSettle();
      engine.dispose();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.neutral);
      expect(ring.ringColor, tokens.pttNeutralRing);
    });

    testWidgets('Ready: accent treatment, enabled, full idle copy', (
      tester,
    ) async {
      await pumpReady(tester);
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.ready);
      expect(ring.ringColor, tokens.actionPrimary);
      expect(ring.enabled, isTrue);
      // ADR-002 A2 splits status copy into a primary line below the ring
      // and a secondary instruction line, rather than one concatenated
      // sentence (pre-ADR-002 rendered them as a single Text).
      expect(find.text(TalkCopy.channelClear), findsWidgets);
      expect(find.text(TalkCopy.holdToTalk), findsWidgets);
    });

    testWidgets('Tuning: neutral treatment', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier).dispatch(
        const BeginTuning(),
      );
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.neutral);
      expect(ring.ringColor, tokens.pttNeutralRing);
      expect(find.text('Changing channel'), findsWidgets);
    });

    testWidgets('Requesting: accent treatment with sweep', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier).dispatch(
        const RequestTransmit(),
      );
      // The requesting treatment's sweep animates continuously by design
      // (ADR-002 A3) — `pumpAndSettle` never settles here, so pump a
      // bounded number of frames instead (mirrors the golden test's fix).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.requesting);
      expect(ring.ringColor, tokens.actionPrimary);
    });

    testWidgets('TX granted: tx treatment, red colour', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted());
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.tx);
      expect(ring.ringColor, tokens.stateTx);
    });

    testWidgets('Receiving: rx treatment, green colour', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const RemoteFloorStarted())
        ..dispatch(const ActiveSpeakerChanged('peer-77'));
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.rx);
      expect(ring.ringColor, tokens.stateRx);
    });

    testWidgets('Latched: latched treatment (lock badge), red colour', (
      tester,
    ) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      container.read(radioStateProvider.notifier)
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keryx-talk-latch')));
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.latched);
      expect(ring.ringColor, tokens.stateTx);
    });

    testWidgets('Denied/busy: neutral ring flash, never overriding a '
        'currently granted TX (Design §4)', (tester) async {
      await pumpReady(tester);
      // A bare denied flash with no TX in progress renders on the ring.
      container.read(radioStateProvider.notifier).dispatch(
        const TransmitDeniedIndicated(),
      );
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.deniedFlash);
      expect(ring.ringColor, tokens.pttNeutralRing);

      // A denied flash concurrent with a granted TX must not recolour the
      // ring away from `tx` — the overlay banner carries the deny, not the
      // ring (Design §4: "A denied flash cannot override a currently
      // granted TX").
      container.read(radioStateProvider.notifier)
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted())
        ..dispatch(const TransmitDeniedIndicated());
      await tester.pumpAndSettle();
      final ring2 = ringWidget(tester);
      expect(ring2.treatment, TalkPttRingTreatment.tx);
      expect(ring2.ringColor, tokens.stateTx);
    });

    testWidgets('No link: neutral treatment on the PTT ring too', (
      tester,
    ) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier).dispatch(
        const LinkDegraded(),
      );
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.neutral);
      expect(ring.ringColor, tokens.pttNeutralRing);
    });

    testWidgets('Emergency: banner overlay only, does not recolour the '
        'ring (Design §4 "overlay, not replacement")', (tester) async {
      await pumpReady(tester);
      final TalkPttRingTreatment before = ringWidget(tester).treatment;
      final Color beforeColor = ringWidget(tester).ringColor;
      container.read(radioStateProvider.notifier).dispatch(
        const EmergencyPinned(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Emergency active'), findsOneWidget);
      final ring = ringWidget(tester);
      expect(ring.treatment, before);
      expect(ring.ringColor, beforeColor);
    });

    testWidgets('Permission denied: neutral treatment on the PTT ring too', (
      tester,
    ) async {
      host.emit(const RadioHostSnapshot(micPermissionDenied: true));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final ring = ringWidget(tester);
      expect(ring.treatment, TalkPttRingTreatment.neutral);
      expect(ring.ringColor, tokens.pttNeutralRing);
    });

    testWidgets('Denied/busy overlay: amber block icon and colour', (
      tester,
    ) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted())
        ..dispatch(const TransmitDeniedIndicated());
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final icon = overlayIcon(tester, 'block');
      expect(icon.icon, Icons.block);
      expect(icon.color, tokens.stateWarning);
    });

    testWidgets('Latched overlay: red lock icon and colour', (tester) async {
      await pumpReady(tester);
      await tester.startGesture(
        tester.getCenter(find.byKey(const Key('keryx-talk-ptt-disc'))),
      );
      await tester.pump();
      container.read(radioStateProvider.notifier)
        ..dispatch(const RequestTransmit())
        ..dispatch(const TransmitGranted());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('keryx-talk-latch')));
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final icon = overlayIcon(tester, 'lock');
      expect(icon.icon, Icons.lock);
      expect(icon.color, tokens.stateTx);
    });

    testWidgets('Emergency overlay: distinct orange priority icon and '
        'colour, not the shared amber warning colour', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier).dispatch(
        const EmergencyPinned(),
      );
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final icon = overlayIcon(tester, 'warning');
      expect(icon.icon, Icons.priority_high);
      expect(icon.color, tokens.stateEmergency);
      expect(icon.color, isNot(tokens.stateWarning));
    });

    testWidgets('Permission denied overlay: mic-off icon and colour', (
      tester,
    ) async {
      host.emit(const RadioHostSnapshot(micPermissionDenied: true));
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final tokens = KeryxUxTokens.dark;
      final icon = overlayIcon(tester, 'mic_off');
      expect(icon.icon, Icons.mic_off);
      expect(icon.color, tokens.stateWarning);
    });

    testWidgets('Service fault overlay: error icon and colour', (
      tester,
    ) async {
      final engine = _newEngine();
      host.emit(
        RadioHostSnapshot(
          floorEngine: engine,
          serviceFaultMessage: 'Background service unavailable',
        ),
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      engine.dispose();
      final tokens = KeryxUxTokens.dark;
      final icon = overlayIcon(tester, 'error');
      expect(icon.icon, Icons.error_outline);
      expect(icon.color, tokens.stateWarning);
    });
  });

  group('effective route label (Technical §7)', () {
    testWidgets('unresolved route is Connecting, never AUTO; configured '
        'AUTO still shows', (tester) async {
      await pumpReady(tester);
      expect(find.textContaining('Route Connecting'), findsOneWidget);
      expect(find.textContaining('Configured AUTO'), findsOneWidget);
      expect(find.textContaining('Route AUTO'), findsNothing);
    });

    testWidgets('resolved LOCAL renders Route LOCAL', (tester) async {
      await pumpReady(tester);
      container.read(radioStateProvider.notifier).dispatch(
        const SetMode(RadioMode.local),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Route LOCAL'), findsOneWidget);
      expect(find.textContaining('Route AUTO'), findsNothing);
      expect(find.textContaining('Route Connecting'), findsNothing);
    });
  });

  group('VT-015 — audio truthfulness', () {
    testWidgets('no signal-quality or roster count is presented as a '
        'verified value when unavailable', (tester) async {
      await pumpReady(tester);
      // Default reducer mode is AUTO; drive unavailable roster via LINKED.
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

    testWidgets(
      'TASK-057: content scrolls instead of overflowing at 320 lp width '
      'and system text scale 2.0',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpReady(tester);
        expect(tester.takeException(), isNull);
        // The scroll view exists and (at this extreme text scale) the
        // content genuinely exceeds the viewport, so it must actually be
        // scrollable rather than merely present.
        expect(find.byType(SingleChildScrollView), findsOneWidget);
        // The primary PTT surface must still be reachable by scrolling to
        // it — not merely rendered off-screen and inaccessible.
        await tester.scrollUntilVisible(
          find.byKey(const Key('keryx-talk-ptt-disc')),
          200,
        );
        expect(find.byKey(const Key('keryx-talk-ptt-disc')), findsOneWidget);
      },
    );

    testWidgets(
      'TASK-057: content renders without overflow in landscape at a small '
      'height',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(640, 320));
        await pumpReady(tester);
        expect(tester.takeException(), isNull);
        addTearDown(() => tester.binding.setSurfaceSize(null));
      },
    );

    testWidgets(
      'TASK-074: at 360x640 dp and text scale 1.0, the channel card, PTT '
      'ring and status line are all visible without scrolling (ADR-002 A3)',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.platformDispatcher.textScaleFactorTestValue = 1.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpReady(tester);
        expect(tester.takeException(), isNull);

        const viewport = Rect.fromLTWH(0, 0, 360, 640);
        for (final key in const [
          'keryx-talk-channel-card',
          'keryx-talk-ptt-disc',
          'keryx-talk-status-line',
        ]) {
          final finder = find.byKey(Key(key));
          expect(finder, findsOneWidget, reason: 'missing $key');
          final rect = tester.getRect(finder);
          expect(
            viewport.contains(rect.topLeft) &&
                viewport.contains(rect.bottomRight),
            isTrue,
            reason: '$key rect $rect not fully within viewport $viewport '
                '(without scrolling)',
          );
        }
      },
    );
  });

  group('TASK-057 round 2 — responsive matrix + rendered guidelines', () {
    testWidgets(
      'renders without exception across the full responsive matrix '
      '(320 lp, larger phone, landscape, text scale 2.0)',
      (tester) async {
        await expectResponsiveMatrix(tester, (t, size) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1.0;
          await pumpReady(t);
        });
      },
    );

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(dark)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReady(tester, brightness: Brightness.dark);
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(light)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReady(tester, brightness: Brightness.light);
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });
  });

  group('TASK-068 — real header callbacks, not shell-owned geometry', () {
    // The defect this task closes: the app-shell composition root used to
    // intercept these header taps with invisible overlays positioned by
    // hardcoded geometry matching this screen's own layout (TASK-052's
    // Review_Findings — proven fragile by a +100dp overlay shift leaving
    // every overlay-based test green while a real-centre-tap probe failed).
    // The actual regression guard for that fragility is proving the
    // callback fires via a real tap on the real button *after* this
    // screen's own internal layout has shifted — not merely that the
    // button renders.
    Widget wrapWithExtraHeaderPadding(Widget talkScreen) => Padding(
      padding: const EdgeInsets.only(top: 137),
      child: talkScreen,
    );

    testWidgets(
      'onOpenPicker fires from a real tap even after the header is wrapped '
      'in extra padding (simulated future layout drift)',
      (tester) async {
        var pickerTaps = 0;
        await tester.pumpWidget(
          build(
            onOpenPicker: () => pickerTaps++,
            wrapHome: wrapWithExtraHeaderPadding,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('keryx-talk-picker')));
        await tester.pump();
        expect(pickerTaps, 1);
      },
    );

    testWidgets(
      'onOpenStations fires from a real tap even after the header is '
      'wrapped in extra padding (simulated future layout drift)',
      (tester) async {
        var stationsTaps = 0;
        await tester.pumpWidget(
          build(
            onOpenStations: () => stationsTaps++,
            wrapHome: wrapWithExtraHeaderPadding,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('keryx-talk-stations')));
        await tester.pump();
        expect(stationsTaps, 1);
      },
    );

    testWidgets(
      'onOpenRadioControls fires from a real tap even after the header is '
      'wrapped in extra padding (simulated future layout drift) — TASK-068 '
      "gives Radio Controls a real header slot, not a bottom-left overlay",
      (tester) async {
        var radioControlsTaps = 0;
        await tester.pumpWidget(
          build(
            onOpenRadioControls: () => radioControlsTaps++,
            wrapHome: wrapWithExtraHeaderPadding,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('keryx-talk-radio-controls')));
        await tester.pump();
        expect(radioControlsTaps, 1);
      },
    );

    testWidgets('a null onOpenPicker/onOpenStations renders the buttons '
        'disabled rather than throwing on tap', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      final IconButton picker = tester.widget<IconButton>(
        find.byKey(const Key('keryx-talk-picker')),
      );
      final TextButton stations = tester.widget<TextButton>(
        find.byKey(const Key('keryx-talk-stations')),
      );
      expect(picker.onPressed, isNull);
      expect(stations.onPressed, isNull);
    });

    testWidgets(
      'a null onOpenRadioControls omits the radio-controls affordance '
      'entirely (ADR-002 A2 — rendered only when the callback is non-null)',
      (tester) async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('keryx-talk-radio-controls')),
          findsNothing,
        );
      },
    );
  });
}
