import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/event_qr/qr_export_screen.dart';
import 'package:keryx/features/event_qr/qr_scan_screen.dart';
// `face.dart`'s barrel also exports `roster.dart`'s own `StationInfo` (a
// distinct display-layer type, same field shape) — hidden here so the
// session-layer `StationInfo` imported below is the unambiguous one this
// file means every time it says `StationInfo` unqualified.
import 'package:keryx/features/face/face.dart' hide StationInfo;
import 'package:keryx/features/settings_panel/back_panel_screen.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

/// TASK-037 acceptance criterion 1 ("`LocalFloorTransport` no longer
/// referenced by `FaceScreen`") is covered structurally, not by a runtime
/// assertion here: `lib/features/face/local_floor_transport.dart` was
/// deleted in this task (nothing under `lib/**`/`test/**` referenced it
/// beyond that file and the old `face_screen.dart`, confirmed by a repo-wide
/// grep before deletion) and `face.dart`'s barrel no longer exports it —
/// `flutter analyze` would fail this file's imports otherwise.

/// A silent, single-device [FloorTransport] — enough to satisfy
/// [FloorEngine]'s constructor for a [FakeSessionHost] without touching any
/// real transport. Mirrors the now-deleted `LocalFloorTransport`'s shape,
/// just without FaceScreen depending on it directly any more.
class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void dispose() => unawaited(_incoming.close());
}

/// Hand-written [SessionHost] double — see `session_host.dart`'s dartdoc
/// for why this is the seam TASK-037 injects rather than a mock of
/// `RadioSessionController` itself (real I/O, cannot run under
/// `flutter test`). Records every call FaceScreen makes so tests can
/// assert on the wiring without any network/platform dependency.
class FakeSessionHost implements SessionHost {
  FakeSessionHost({
    required this.localPeerId,
    required this.callsign,
    required this.settings,
  });

  final String localPeerId;
  final String callsign;
  final KeryxSettings settings;

  final _NullFloorTransport _transport = _NullFloorTransport();
  late final FloorEngine _engine = FloorEngine(
    localPeerId: localPeerId,
    transport: _transport,
    clock: const WallClock(),
    tot: Duration(seconds: settings.totSeconds),
    busyLockout: settings.busyLockout,
    callsign: callsign,
  );

  final StreamController<List<StationInfo>> _stations =
      StreamController<List<StationInfo>>.broadcast();

  bool startCalled = false;
  bool disposeCalled = false;
  int retuneCallCount = 0;
  final List<EventLinkPayload> joinEventCalls = <EventLinkPayload>[];

  @override
  FloorEngine get floorEngine => _engine;

  @override
  Stream<List<StationInfo>> get stations => _stations.stream;

  /// Test seam: pushes a roster update as if signaling reported it.
  void emitStations(List<StationInfo> next) {
    if (!_stations.isClosed) _stations.add(next);
  }

  @override
  Future<void> start() async {
    startCalled = true;
  }

  @override
  Future<void> retune({required int channel, required int code}) async {
    retuneCallCount++;
  }

  @override
  Future<void> joinEvent(EventLinkPayload payload) async {
    joinEventCalls.add(payload);
  }

  @override
  Future<void> dispose() async {
    disposeCalled = true;
    _engine.dispose();
    _transport.dispose();
    await _stations.close();
  }
}

/// Records every pushed route so a test can inspect (or manually
/// `buildPage`) it without ever letting the real destination widget — in
/// particular `EventQrScanScreen`'s `MobileScanner`, which has no camera
/// platform channel under `flutter test` — actually mount. This mirrors
/// this repo's own standing convention (see
/// `test/features/event_qr/qr_scan_screen_test.dart`) of testing the QR
/// scan wiring without ever building the camera widget.
class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushed = route;
  }
}

/// Boots a [FaceScreen] with fakes for the session and audio sink, so no
/// test in this file touches real I/O, real storage, or a real SoLoud
/// backend — matching this task's own acceptance criterion that widget
/// tests use fakes for both.
class _Harness {
  final List<FakeSessionHost> sessions = <FakeSessionHost>[];
  final RecordingAudioSink sink = RecordingAudioSink();
  final InMemorySettingsStore store = InMemorySettingsStore();
  final _RecordingNavigatorObserver observer = _RecordingNavigatorObserver();

  /// Review round-1 finding (c): `audioSinkDisposer` is already an
  /// injected function (see `FaceScreen.audioSinkDisposer`'s dartdoc for
  /// why disposal can't go through the `AudioSink` interface itself), so
  /// recording the call here is a one-line way to make sink disposal
  /// directly assertable instead of only implied.
  bool audioSinkDisposeCalled = false;

  SessionHost _sessionFactory({
    required String localPeerId,
    required String callsign,
    required KeryxSettings settings,
    required void Function(RadioEvent event) dispatch,
    required int initialChannel,
    required int initialCode,
  }) {
    final host = FakeSessionHost(
      localPeerId: localPeerId,
      callsign: callsign,
      settings: settings,
    );
    sessions.add(host);
    return host;
  }

  Future<AudioSink> _audioSinkFactory() async => sink;

  Future<void> _audioSinkDisposer(AudioSink sink) async {
    audioSinkDisposeCalled = true;
  }

  /// `IdentityRepository(SecureIdentityStore())`'s real secure-storage
  /// platform channel never answers under this project's `flutter test`
  /// host (no plugin implementation registered there) — see
  /// `FaceScreen.identityFactory`'s own dartdoc. A fixed, deterministic
  /// identity keeps every test fast and reproducible regardless.
  Future<DeviceIdentity> _identityFactory() async => DeviceIdentity(
    installUuid: 'test-install-uuid',
    peerId: 'test-peer-id',
    callsign: Callsign.parse('TEST-1'),
  );

  Widget build() {
    return ProviderScope(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        routes: <String, WidgetBuilder>{
          backPanelRouteName: (context) => const BackPanelScreen(),
        },
        home: Scaffold(
          body: FaceScreen(
            sessionFactory: _sessionFactory,
            audioSinkFactory: _audioSinkFactory,
            audioSinkDisposer: _audioSinkDisposer,
            identityFactory: _identityFactory,
          ),
        ),
      ),
    );
  }

  Future<void> boot(WidgetTester tester) async {
    // Portrait-ish size, matching `face_view_test.dart`'s own convention —
    // the default 800x600 test window is landscape, which routes the face
    // through `_LandscapeBody`'s `RotatedBox`/`FittedBox` nesting and makes
    // a couple of the smaller tap targets (e.g. the settings key) miss
    // their hit test under the default window.
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
  }
}

Future<void> _flipToStations(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('keryx-status-strip-stn')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'boots to the face with fakes for session/sink; no real I/O',
    (tester) async {
      final harness = _Harness();
      await harness.boot(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(FaceView), findsOneWidget);
      expect(harness.sessions, hasLength(1));
      expect(harness.sessions.single.startCalled, isTrue);
    },
  );

  group('station roster (criterion 2)', () {
    testWidgets(
      'empty roster still renders "NO OTHER STATIONS"',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        await _flipToStations(tester);

        expect(find.text('NO OTHER STATIONS'), findsOneWidget);
      },
    );

    testWidgets(
      'a faked session stations stream drives live join/depart entries',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        final session = harness.sessions.single;

        session.emitStations(const <StationInfo>[
          StationInfo(peerId: 'p1', callsign: 'ALPHA-1'),
          StationInfo(peerId: 'p2', callsign: 'BRAVO-2'),
        ]);
        await tester.pumpAndSettle();
        await _flipToStations(tester);

        expect(find.text('ALPHA-1'), findsOneWidget);
        expect(find.text('BRAVO-2'), findsOneWidget);

        // Depart: BRAVO-2 leaves the roster.
        session.emitStations(const <StationInfo>[
          StationInfo(peerId: 'p1', callsign: 'ALPHA-1'),
        ]);
        await tester.pumpAndSettle();

        expect(find.text('ALPHA-1'), findsOneWidget);
        expect(find.text('BRAVO-2'), findsNothing);
      },
    );
  });

  group('settings (criterion 3)', () {
    testWidgets(
      'onSettings navigates to BackPanelScreen and back',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);

        // `warnIfMissed: false`: this key sits inside a `FittedBox`-scaled
        // `Row` (`FaceView._controlsRegion`) whose `getCenter`-derived tap
        // point lands a hair outside the strict hit-test chain for the
        // outer `Container` even though the tap correctly reaches (and
        // fires) the `GestureDetector` around it — same false-positive
        // `flutter_test` reports for any transform-scaled key cap here.
        await tester.tap(
          find.byKey(const Key('keryx-ptt-key-settings')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(find.byType(BackPanelScreen), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(BackPanelScreen), findsNothing);
        expect(find.byType(FaceView), findsOneWidget);
      },
    );

    testWidgets(
      'a session-affecting settings change made through settingsProvider '
      'is observed by the face without restart: session is torn down and '
      'rebuilt with the new settings',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        expect(harness.sessions, hasLength(1));
        final first = harness.sessions.single;

        final container = ProviderScope.containerOf(
          tester.element(find.byType(FaceScreen)),
        );
        final current = container.read(settingsProvider).requireValue;
        await tester.runAsync(() async {
          await container
              .read(settingsProvider.notifier)
              .save(current.copyWith(mode: RadioMode.local));
          // The rebuild chain this triggers (`_onSettingsChanged` ->
          // `_maybeRebuildSession` -> `_startSession`) is a fire-and-forget
          // async chain unrelated to Flutter's frame scheduler, so
          // `pumpAndSettle` alone does not reliably drain it — give it a
          // real, short window to actually run.
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        expect(first.disposeCalled, isTrue);
        expect(harness.sessions, hasLength(2));
        expect(harness.sessions.last.settings.mode, RadioMode.local);
      },
    );

    testWidgets(
      'a non-session-affecting settings change does not rebuild the session',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        expect(harness.sessions, hasLength(1));

        final container = ProviderScope.containerOf(
          tester.element(find.byType(FaceScreen)),
        );
        final current = container.read(settingsProvider).requireValue;
        await container
            .read(settingsProvider.notifier)
            .save(current.copyWith(squelchLevel: 8));
        await tester.pumpAndSettle();

        expect(harness.sessions, hasLength(1));
      },
    );
  });

  group('event QR (criterion 4)', () {
    testWidgets(
      'scan icon pushes the scanner screen, whose onTuned callback calls '
      'joinEvent on the active session',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        await _flipToStations(tester);

        // Tapping only *pushes* the route (`Navigator.push` runs
        // synchronously inside the tap callback) — we deliberately do not
        // pump again before inspecting it, so `EventQrScanScreen`'s
        // `MobileScanner` (real camera platform channel, unavailable under
        // `flutter test`) never actually builds/mounts.
        await tester.tap(find.byKey(const Key('keryx-station-panel-scan')));

        final route = harness.observer.lastPushed;
        expect(route, isA<MaterialPageRoute<void>>());
        final page = (route! as MaterialPageRoute<void>).buildPage(
          tester.element(find.byType(FaceScreen)),
          const AlwaysStoppedAnimation<double>(1),
          const AlwaysStoppedAnimation<double>(1),
        );
        // `MaterialPageRoute.buildPage` wraps our builder's widget in a
        // route-scoping `Semantics` node — unwrap it to reach the `Scaffold`
        // our own `_onScanQr` builder actually returned.
        final scaffold = (page as Semantics).child! as Scaffold;
        final scanScreen = scaffold.body! as EventQrScanScreen;

        const payload = NumberedEventLink(
          region: 'za-cpt',
          channel: 12,
          code: 5,
        );
        scanScreen.onTuned(payload);

        expect(harness.sessions.single.joinEventCalls, contains(payload));
      },
    );

    testWidgets(
      'export icon reaches a rendered EventQrExportScreen',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        await _flipToStations(tester);

        await tester.tap(find.byKey(const Key('keryx-station-panel-export')));
        await tester.pumpAndSettle();

        expect(find.byType(EventQrExportScreen), findsOneWidget);
        expect(find.textContaining('keryx://join'), findsOneWidget);
      },
    );
  });

  group('sound (criterion 5)', () {
    testWidgets(
      'SfxEngine/SfxProjection are wired over the injected sink; '
      'power-on plays the powerOn cue',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);

        expect(
          harness.sink.oneShots.map((event) => event.id),
          contains(SfxId.powerOn),
        );
      },
    );
  });

  group('disposal (criterion 6)', () {
    testWidgets(
      'tearing the face down disposes the session and the sink, and leaves '
      'no leaked subscriptions/timers',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        final session = harness.sessions.single;

        // Replace the whole tree — this disposes `FaceScreen` and every
        // widget beneath it, exactly like a real navigation-away would.
        // `testWidgets` runs the whole body under `FakeAsync` (via
        // `TestWidgetsFlutterBinding`), which fails the test if a
        // `Timer.periodic` (here, `_sfxTick`, `SfxEngine`'s duck-envelope
        // driver) is still pending when the test ends — so this test
        // passing at all is itself the proof that `_sfxTick.cancel()` in
        // `dispose()` actually ran. Review round-1 finding (c): that proof
        // was previously only implicit; it is now stated rather than left
        // to be rediscovered.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(session.disposeCalled, isTrue);
        // `SfxEngine`/`SfxProjection` have no directly-observable "disposed"
        // flag of their own (see `sound.dart`) — `audioSinkDisposer` is the
        // one seam FaceScreen exposes for the whole sound pipeline's
        // teardown, so it stands in for "engine + projection + sink were
        // all torn down together" here.
        expect(harness.audioSinkDisposeCalled, isTrue);
      },
    );
  });

  group('touch targets (DS L134)', () {
    testWidgets(
      'the station-panel QR scan/export icons meet the 48dp minimum '
      'tap-target size',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        await _flipToStations(tester);

        // Scoped to just these two icons rather than a whole-screen
        // `meetsGuideline(androidTapTargetGuideline)` check: several other
        // controls elsewhere on the face (e.g. the PTT key row's compact
        // keys, the STN status-strip button) are pre-existing,
        // out-of-territory widgets this task did not touch and is not
        // charged with fixing — a global guideline check would fail on
        // those too and misattribute the finding. DS L134 is checked
        // exactly where this task's own fix (a) applies.
        //
        // Round-2 review finding (h): `tester.getSize` is NOT a valid probe
        // here — under Material 3, `IconButton` routes through
        // `ButtonStyleButton`'s `_InputPadding`, which pads the rendered
        // hit-test box to 48x48 under `MaterialTapTargetSize.padded`
        // regardless of the `constraints` actually passed to the
        // `IconButton`. That means `getSize` would return >= 48 even with
        // the pre-fix `minWidth: 28, minHeight: 28` — the assertion must
        // instead read the `IconButton.constraints` property directly,
        // which is the value (a) actually changed. Mutation-verified:
        // reverting `station_panel.dart`'s constraints to 28/28 fails this
        // test (widget property visibly 28 < 48); with the fix in place it
        // passes.
        final scanButton = tester.widget<IconButton>(
          find.byKey(const Key('keryx-station-panel-scan')),
        );
        final exportButton = tester.widget<IconButton>(
          find.byKey(const Key('keryx-station-panel-export')),
        );
        expect(scanButton.constraints?.minWidth, greaterThanOrEqualTo(48));
        expect(scanButton.constraints?.minHeight, greaterThanOrEqualTo(48));
        expect(exportButton.constraints?.minWidth, greaterThanOrEqualTo(48));
        expect(exportButton.constraints?.minHeight, greaterThanOrEqualTo(48));
      },
    );
  });

  group('QR entry point reachability (review round-1 finding (b))', () {
    testWidgets(
      'the scan/export icons survive the 5s auto-flip window once the '
      'panel has been interacted with',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        await _flipToStations(tester);

        // Round-2 review finding (i): the original version of this test
        // pumped only ~4s total from the `_flipToStations` tap in one big
        // jump, which (a) never exceeded the original 5s window even with
        // NO interaction reset at all, and (b) even when the window is
        // exceeded, `GlassFlipper`'s flip-back is a 320ms
        // `AnimationController.animateTo(0)` — a single large `pump` only
        // renders one frame *after* the jump and never gives that
        // in-flight animation the intermediate frames it needs to
        // actually settle to "front", so the "back" panel (and its scan
        // icon) stays visible in the tree even once the un-reset timer
        // has fired. Discriminating version: elapse most of the
        // *original* window first (4s, no interaction), THEN interact,
        // THEN pump forward in small increments (so any flip-back
        // animation that starts gets to run to completion) past the
        // original 5s deadline. The panel can only still be showing
        // because the interaction restarted the clock via
        // `onInteraction`. Mutation-verified: deleting
        // `onInteraction: flipController.flipToStations` from
        // `face_view.dart` fails this test (the un-reset timer fires at
        // ~5s, the flip-back animation settles during the granular pumps,
        // and the scan icon is gone by the final check); with the fix in
        // place it passes.
        await tester.pump(const Duration(seconds: 4));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('keryx-station-panel'))),
        );
        await gesture.up();
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(
          find.byKey(const Key('keryx-station-panel-scan')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('keryx-station-panel-scan')));
        expect(harness.observer.lastPushed, isA<MaterialPageRoute<void>>());
      },
    );

    testWidgets(
      'pushing the scan screen pauses the auto-flip; returning resumes a '
      'fresh window',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        await _flipToStations(tester);

        await tester.tap(find.byKey(const Key('keryx-station-panel-scan')));
        await tester.pumpAndSettle();

        // While the scan screen covers the panel, the auto-flip must not
        // fire in the background — advancing well past 5s must not pop
        // the still-open scan route.
        await tester.pump(const Duration(seconds: 6));
        expect(find.byType(EventQrScanScreen), findsOneWidget);

        await tester.pageBack();
        await tester.pumpAndSettle();

        // A fresh 5s window on return: just under 5s later the panel is
        // still showing stations.
        await tester.pump(const Duration(seconds: 4));
        expect(
          find.byKey(const Key('keryx-station-panel')),
          findsOneWidget,
        );
      },
    );
  });

  group('_startSession re-entrancy (review round-1 finding (d))', () {
    testWidgets(
      'two session-affecting settings changes fired without pumping between '
      'them leave exactly one undisposed session',
      (tester) async {
        final harness = _Harness();
        await harness.boot(tester);
        expect(harness.sessions, hasLength(1));
        final original = harness.sessions.single;

        final container = ProviderScope.containerOf(
          tester.element(find.byType(FaceScreen)),
        );
        final current = container.read(settingsProvider).requireValue;

        await tester.runAsync(() async {
          // Two session-affecting changes, fired back-to-back with no
          // await/pump between them — both `_maybeRebuildSession` calls
          // race into `_startSession` while the first is still suspended
          // in `session.start()` (via `FakeSessionHost.start`'s own
          // `async`). Without the generation guard, the first call's
          // session/subscriptions would never be disposed.
          final a = container
              .read(settingsProvider.notifier)
              .save(current.copyWith(mode: RadioMode.local));
          final b = container
              .read(settingsProvider.notifier)
              .save(current.copyWith(mode: RadioMode.linked));
          await Future.wait(<Future<void>>[a, b]);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(original.disposeCalled, isTrue);
        // Exactly one of the two raced sessions ends up disposed=false
        // (the survivor); every other session created along the way must
        // be disposed — none leaked.
        final undisposed = harness.sessions.where((s) => !s.disposeCalled);
        expect(undisposed, hasLength(1));
      },
    );
  });
}
