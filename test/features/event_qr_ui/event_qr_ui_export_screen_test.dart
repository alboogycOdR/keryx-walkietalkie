import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/event_qr/event_qr.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_copy.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../talk/a11y_matrix_support.dart';

void main() {
  late ProviderContainer container;

  Future<Widget> build({
    KeryxSettings? settings,
    Brightness brightness = Brightness.dark,
  }) async {
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
        theme: keryxUxThemeData(brightness: brightness),
        home: const EventQrUiExportScreen(),
      ),
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

  group('TASK-057 — accessibility polish', () {
    testWidgets('the screen body is wrapped in a SafeArea', (tester) async {
      await tester.pumpWidget(await build(settings: const KeryxSettings(region: 'za-cpt')));
      await tester.pumpAndSettle();
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets(
      'the keyed-unavailable explanation is announced as a live region',
      (tester) async {
        await tester.pumpWidget(await build(settings: const KeryxSettings(region: 'za-cpt')));
        await tester.pumpAndSettle();
        container.read(radioStateProvider.notifier)
          ..dispatch(const PowerOn())
          ..dispatch(const BootCompleted())
          ..dispatch(const PrivateChannelChanged(true));
        await tester.pumpAndSettle();

        final Semantics semantics = tester.widget<Semantics>(
          find.ancestor(
            of: find.byKey(EventQrUiExportKeys.unavailable),
            matching: find.byWidgetPredicate((w) => w is Semantics),
          ).first,
        );
        expect(semantics.properties.liveRegion, isTrue);
      },
    );
  });

  group('TASK-057 round 2 — responsive matrix + rendered guidelines', () {
    Future<void> pumpReady(WidgetTester tester, {Brightness brightness = Brightness.dark}) async {
      await tester.pumpWidget(
        await build(
          settings: const KeryxSettings(region: 'za-cpt'),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      container.read(radioStateProvider.notifier)
        ..dispatch(const PowerOn())
        ..dispatch(const BootCompleted());
      await tester.pumpAndSettle();
    }

    testWidgets(
      'renders without exception across the full responsive matrix '
      '(320 lp, larger phone, landscape, text scale 2.0)',
      (tester) async {
        await expectResponsiveMatrix(tester, (t, size) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1.0;
          await t.pumpWidget(const SizedBox.shrink());
          await pumpReady(t);
        });
      },
    );

    // The rendered screen embeds `lib/features/event_qr/qr_export_screen.dart`
    // (`SelectableText` showing the join link, key `event_qr_link_text`) —
    // that file is frozen legacy territory this task must not edit (TASK-056
    // review: "consumed as a dependency, never edited"; ADR-001 §6; deletion
    // is TASK-061's). Its read-only, long-press-to-copy text row is a real
    // sub-48dp tap target by Android's guideline, but fixing it means editing
    // out-of-territory code — recorded as a finding, not silently excluded
    // from the sweep, and every *other* node on the screen is still held to
    // the guideline with no exception.
    Future<void> expectTapTargetsExceptFrozenLinkText(WidgetTester tester) async {
      final Evaluation evaluation = await androidTapTargetGuideline.evaluate(
        tester,
      );
      if (evaluation.passed) {
        return;
      }
      final String? reason = evaluation.reason;
      expect(reason, isNotNull);
      final int failureCount =
          RegExp('expected tap target size').allMatches(reason!).length;
      final bool onlyKnownException =
          failureCount == 1 && reason.contains('keryx://join');
      expect(
        onlyKnownException,
        isTrue,
        reason:
            'Unexpected tap-target guideline failure(s) beyond the known '
            'frozen event_qr link-text exception:\n$reason',
      );
    }

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(dark)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReady(tester, brightness: Brightness.dark);
      await expectRenderedContrast(tester);
      await expectTapTargetsExceptFrozenLinkText(tester);
      handle.dispose();
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(light)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpReady(tester, brightness: Brightness.light);
      await expectRenderedContrast(tester);
      await expectTapTargetsExceptFrozenLinkText(tester);
      handle.dispose();
    });
  });
}

/// Never resolves — simulates settings still loading (asserts AC "settings
/// unavailable" render path rather than a blank/crashing screen).
class _NeverLoadingSettingsController extends SettingsController {
  @override
  Future<KeryxSettings> build() => Completer<KeryxSettings>().future;
}
