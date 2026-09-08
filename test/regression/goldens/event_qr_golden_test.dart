import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/event_qr/event_qr.dart';
import 'package:keryx/features/event_qr_ui/event_qr_permission_gate.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_scan_screen.dart';

import '../../app_shell/fake_radio_host.dart';
import '../../features/event_qr_ui/fake_permission_gate.dart';

/// TASK-058 — Verification §6: golden fixtures for "QR and error states",
/// dark and light. Covers the export screen (a numbered channel, the only
/// currently-working export path) and the scan screen (granted-permission
/// and denied-permission — the latter doubling as one of §6's named "error
/// states").
///
/// A from-scratch, task-owned stand-in for the real `EventQrScanScreen`
/// (which needs `mobile_scanner`'s platform channel, unavailable under
/// `flutter test` — the same reason
/// `test/features/event_qr_ui/event_qr_ui_scan_screen_test.dart` injects an
/// equivalent private stand-in via `EventQrUiScanScreen.scannerBuilder`).
class _FakeScanner extends StatelessWidget {
  const _FakeScanner({super.key, required this.onTuned, this.onInvalid});

  final void Function(EventLinkPayload payload) onTuned;
  final void Function(String reason)? onInvalid;

  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 240,
        child: ColoredBox(color: Colors.black),
      );
}

void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Widget home,
    required Brightness brightness,
    KeryxSettings? settings,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = InMemorySettingsStore();
    if (settings != null) {
      await SettingsRepository(store).save(settings);
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[settingsStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(find.byKey(const Key('qr-golden-root')), matchesGoldenFile('goldens/qr_$name.png'));
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Event QR export — numbered channel ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'export_$suffix',
        brightness: brightness,
        settings: const KeryxSettings(),
        home: KeyedSubtree(
          key: const Key('qr-golden-root'),
          child: EventQrUiExportScreen(now: () => DateTime(2026, 1, 1)),
        ),
      );
    });

    testWidgets('Event QR scan — permission granted ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'scan_granted_$suffix',
        brightness: brightness,
        home: KeyedSubtree(
          key: const Key('qr-golden-root'),
          child: EventQrUiScanScreen(
            host: FakeRadioHost(),
            permissionGate: FakePermissionGate(),
            scannerBuilder: ({key, required onTuned, onInvalid}) =>
                _FakeScanner(key: key, onTuned: onTuned, onInvalid: onInvalid),
          ),
        ),
      );
    });

    testWidgets(
      'Event QR scan — permission denied (§6 named error state) ($suffix)',
      (tester) async {
        await pumpAndGolden(
          tester,
          name: 'scan_denied_$suffix',
          brightness: brightness,
          home: KeyedSubtree(
            key: const Key('qr-golden-root'),
            child: EventQrUiScanScreen(
              host: FakeRadioHost(),
              permissionGate: FakePermissionGate(
                initial: EventQrPermissionState.denied,
              ),
              scannerBuilder: ({key, required onTuned, onInvalid}) =>
                  _FakeScanner(key: key, onTuned: onTuned, onInvalid: onInvalid),
            ),
          ),
        );
      },
    );
  }
}
