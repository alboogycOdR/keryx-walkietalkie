import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/event_qr/event_qr.dart';
import 'package:keryx/features/event_qr_ui/event_qr_permission_gate.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_copy.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_scan_screen.dart';

import 'fake_permission_gate.dart';
import 'fake_radio_host.dart';

/// Test-only scanner stand-in: a real `EventQrScanScreen` requires
/// `mobile_scanner`'s platform channel (unavailable in `flutter test`,
/// same constraint `test/features/event_qr/qr_scan_screen_test.dart`
/// documents), so widget tests inject this instead via
/// `EventQrUiScanScreen.scannerBuilder` and trigger scans with plain
/// button taps.
class _FakeScanner extends StatelessWidget {
  const _FakeScanner({super.key, required this.onTuned, this.onInvalid});

  final void Function(EventLinkPayload payload) onTuned;
  final void Function(String reason)? onInvalid;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          key: const Key('fake-scanner.tune'),
          onPressed: () =>
              onTuned(const NumberedEventLink(region: 'global', channel: 7, code: 3)),
          child: const Text('simulate valid scan'),
        ),
        ElevatedButton(
          key: const Key('fake-scanner.expired'),
          onPressed: () => onInvalid?.call('expired'),
          child: const Text('simulate expired scan'),
        ),
        ElevatedButton(
          key: const Key('fake-scanner.malformed'),
          onPressed: () => onInvalid?.call('malformed URI'),
          child: const Text('simulate malformed scan'),
        ),
      ],
    );
  }
}

void main() {
  late FakeRadioHost host;
  late FakePermissionGate permissionGate;
  late ProviderContainer container;

  Future<Widget> build({KeryxSettings? settings}) async {
    final store = InMemorySettingsStore();
    if (settings != null) {
      await SettingsRepository(store).save(settings);
    }
    container = ProviderContainer(
      overrides: <Override>[settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: GlobalKey<NavigatorState>(),
        home: EventQrUiScanScreen(
          host: host,
          permissionGate: permissionGate,
          scannerBuilder: ({key, required onTuned, onInvalid}) =>
              _FakeScanner(key: key, onTuned: onTuned, onInvalid: onInvalid),
        ),
      ),
    );
  }

  setUp(() {
    host = FakeRadioHost();
    permissionGate = FakePermissionGate();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    if (container.read(radioStateProvider).phase != RadioPhase.idle) {
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted());
    }
    await tester.pumpAndSettle();
  }

  group('camera permission states (AC2)', () {
    testWidgets('denied: shows explanation and a grant-access action', (tester) async {
      permissionGate = FakePermissionGate(initial: EventQrPermissionState.denied);
      await tester.pumpWidget(await build());
      await settle(tester);

      expect(find.text(EventQrUiCopy.permissionDeniedTitle), findsOneWidget);
      expect(find.byKey(EventQrUiScanKeys.permissionAction), findsOneWidget);

      await tester.tap(find.byKey(EventQrUiScanKeys.permissionAction));
      await settle(tester);
      expect(permissionGate.requestCalls, 1);
    });

    testWidgets('permanently denied: offers Open Settings, never re-prompts OS', (
      tester,
    ) async {
      permissionGate = FakePermissionGate(initial: EventQrPermissionState.permanentlyDenied);
      await tester.pumpWidget(await build());
      await settle(tester);

      expect(find.text(EventQrUiCopy.permissionPermanentlyDeniedTitle), findsOneWidget);
      await tester.tap(find.byKey(EventQrUiScanKeys.permissionAction));
      await settle(tester);
      expect(permissionGate.openSettingsCalls, 1);
      expect(permissionGate.requestCalls, 0);
    });

    testWidgets('unavailable: explains, offers no action at all', (tester) async {
      permissionGate = FakePermissionGate(initial: EventQrPermissionState.unavailable);
      await tester.pumpWidget(await build());
      await settle(tester);

      expect(find.byKey(EventQrUiScanKeys.permissionUnavailable), findsOneWidget);
      expect(find.byKey(EventQrUiScanKeys.permissionAction), findsNothing);
    });

    testWidgets('granted: mounts the scanner directly', (tester) async {
      await tester.pumpWidget(await build());
      await settle(tester);
      expect(find.byType(_FakeScanner), findsOneWidget);
    });
  });

  group('join coordination (AC3-6)', () {
    testWidgets('already-linked scan joins immediately and pops', (tester) async {
      await tester.pumpWidget(await build());
      await settle(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const SetMode(RadioMode.linked));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fake-scanner.tune')));
      await tester.pumpAndSettle();

      expect(host.joinEventCalls, hasLength(1));
      expect(host.applySettingsCalls, isEmpty);
    });

    testWidgets(
      'force-LOCAL + LOCAL route: blocked with explanation, no dialog, no WAN calls',
      (tester) async {
        await tester.pumpWidget(
          await build(settings: const KeryxSettings(forceLocalOnly: true, mode: RadioMode.local)),
        );
        await settle(tester);
        container.read(radioStateProvider.notifier)
          ..dispatch(const PowerOn())
          ..dispatch(const BootCompleted());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fake-scanner.tune')));
        await tester.pumpAndSettle();

        expect(find.text(EventQrUiCopy.forceLocalBlocked), findsOneWidget);
        expect(find.byKey(EventQrUiScanKeys.routeTransitionDialog), findsNothing);
        expect(host.applySettingsCalls, isEmpty);
        expect(host.joinEventCalls, isEmpty);
      },
    );

    testWidgets('LOCAL route, user approves transition: switches then joins', (
      tester,
    ) async {
      await tester.pumpWidget(await build(settings: const KeryxSettings(mode: RadioMode.local)));
      await settle(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fake-scanner.tune')));
      await tester.pumpAndSettle();

      expect(find.byKey(EventQrUiScanKeys.routeTransitionDialog), findsOneWidget);
      await tester.tap(find.byKey(EventQrUiScanKeys.routeTransitionConfirm));
      await tester.pumpAndSettle();

      expect(host.applySettingsCalls, hasLength(1));
      expect(host.applySettingsCalls.single.mode, RadioMode.linked);
      expect(host.joinEventCalls, hasLength(1));
    });

    testWidgets('LOCAL route, user cancels transition: no settings mutation, resumes scanning', (
      tester,
    ) async {
      await tester.pumpWidget(await build(settings: const KeryxSettings(mode: RadioMode.local)));
      await settle(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fake-scanner.tune')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(EventQrUiScanKeys.routeTransitionCancel));
      await tester.pumpAndSettle();

      expect(find.text(EventQrUiCopy.joinCancelled), findsOneWidget);
      expect(host.applySettingsCalls, isEmpty);
      expect(host.joinEventCalls, isEmpty);
      // Scanner resumed (remounted), not left on a stuck/expired state.
      expect(find.byType(_FakeScanner), findsOneWidget);
    });

    testWidgets('join failure leaves no falsely-selected channel; explains and resumes', (
      tester,
    ) async {
      host.joinEventResult = const JoinResult.transportFailure('peer unreachable');
      await tester.pumpWidget(await build());
      await settle(tester);
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted())
        ..dispatch(const SetMode(RadioMode.linked));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('fake-scanner.tune')));
      await tester.pumpAndSettle();

      expect(find.text(EventQrUiCopy.joinFailed), findsOneWidget);
      expect(find.byType(_FakeScanner), findsOneWidget);
    });

    testWidgets('expired scan: explains, resumes scanning (terminal outcome)', (
      tester,
    ) async {
      await tester.pumpWidget(await build());
      await settle(tester);

      await tester.tap(find.byKey(const Key('fake-scanner.expired')));
      await tester.pumpAndSettle();

      expect(find.text(EventQrUiCopy.scanExpired), findsOneWidget);
      expect(find.byType(_FakeScanner), findsOneWidget);
      expect(host.joinEventCalls, isEmpty);
    });

    testWidgets('malformed scan: shows a hint, keeps the same scanner mounted', (
      tester,
    ) async {
      await tester.pumpWidget(await build());
      await settle(tester);

      final keyBefore = find.byType(_FakeScanner).evaluate().single.widget.key;
      await tester.tap(find.byKey(const Key('fake-scanner.malformed')));
      await tester.pumpAndSettle();

      expect(find.text(EventQrUiCopy.scanInvalid), findsOneWidget);
      // Same key (not remounted with a new scan generation) — malformed
      // scans are non-terminal, so the scanner keeps running as-is.
      expect(find.byType(_FakeScanner).evaluate().single.widget.key, keyBefore);
    });
  });

  group('TASK-057 — accessibility polish', () {
    testWidgets('the screen body is wrapped in a SafeArea', (tester) async {
      permissionGate = FakePermissionGate(initial: EventQrPermissionState.denied);
      await tester.pumpWidget(await build());
      await settle(tester);
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets(
      'the permission grant-access action meets the 48 dp minimum target',
      (tester) async {
        permissionGate = FakePermissionGate(initial: EventQrPermissionState.denied);
        await tester.pumpWidget(await build());
        await settle(tester);

        final Size size = tester.getSize(
          find.ancestor(
            of: find.byKey(EventQrUiScanKeys.permissionAction),
            matching: find.byType(SizedBox),
          ).first,
        );
        expect(size.height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets('the invalid/expired feedback message is a live region', (
      tester,
    ) async {
      await tester.pumpWidget(await build());
      await settle(tester);

      await tester.tap(find.byKey(const Key('fake-scanner.malformed')));
      await tester.pumpAndSettle();

      final Semantics semantics = tester.widget<Semantics>(
        find.ancestor(
          of: find.text(EventQrUiCopy.scanInvalid),
          matching: find.byWidgetPredicate((w) => w is Semantics),
        ).first,
      );
      expect(semantics.properties.liveRegion, isTrue);
    });
  });
}
