import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/event_qr/event_qr.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_copy.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
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
      child: const MaterialApp(home: EventQrUiExportScreen()),
    );
  }

  testWidgets('numbered channel: renders the existing export screen with a real QR', (
    tester,
  ) async {
    await tester.pumpWidget(await build(settings: const KeryxSettings(region: 'za-cpt')));
    await tester.pumpAndSettle();
    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted());
    await tester.pumpAndSettle();

    expect(find.byKey(EventQrUiExportKeys.numberedExport), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    final textWidget = tester.widget<SelectableText>(
      find.byKey(const Key('event_qr_link_text')),
    );
    final decoded = decodeEventLink(textWidget.data!) as EventLinkDecoded;
    expect((decoded.payload as NumberedEventLink).region, 'za-cpt');
    expect(find.byKey(EventQrUiExportKeys.unavailable), findsNothing);
  });

  testWidgets('keyed (private) channel: surfaced as unavailable, never faked as working', (
    tester,
  ) async {
    await tester.pumpWidget(await build());
    await tester.pumpAndSettle();
    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted())
      ..dispatch(const PrivateChannelChanged(true));
    await tester.pumpAndSettle();

    expect(find.byKey(EventQrUiExportKeys.unavailable), findsOneWidget);
    expect(find.text(EventQrUiCopy.keyedExportUnavailableTitle), findsOneWidget);
    expect(find.byKey(EventQrUiExportKeys.numberedExport), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('settings still loading: unavailable with a reason, not a blank screen', (
    tester,
  ) async {
    final store = InMemorySettingsStore();
    container = ProviderContainer(
      overrides: <Override>[
        settingsProvider.overrideWith(_NeverLoadingSettingsController.new),
        settingsStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: EventQrUiExportScreen()),
      ),
    );
    await tester.pump();

    expect(find.byKey(EventQrUiExportKeys.unavailable), findsOneWidget);
    expect(find.text(EventQrUiCopy.exportSettingsUnavailable), findsOneWidget);
  });
}

/// Never resolves — simulates settings still loading (asserts AC "settings
/// unavailable" render path rather than a blank/crashing screen).
class _NeverLoadingSettingsController extends SettingsController {
  @override
  Future<KeryxSettings> build() => Completer<KeryxSettings>().future;
}
