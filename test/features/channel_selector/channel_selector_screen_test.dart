import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';

import '../talk/a11y_matrix_support.dart';
import 'fake_radio_host.dart';

void main() {
  late FakeRadioHost host;
  late InMemorySettingsStore store;
  late ProviderContainer container;
  bool cancelled = false;

  Future<void> seedMemory(List<TunedChannel> entries) async {
    final settings = KeryxSettings(channelMemory: entries);
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(settings.toJson()),
    );
  }

  Widget build({Brightness brightness = Brightness.dark}) {
    container = ProviderContainer(
      overrides: <Override>[settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: ChannelSelectorScreen(
          host: host,
          onCancel: () => cancelled = true,
        ),
      ),
    );
  }

  setUp(() {
    host = FakeRadioHost();
    store = InMemorySettingsStore();
    cancelled = false;
  });

  testWidgets('renders current channel, direct-entry fields and recall section', (
    tester,
  ) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(find.byKey(ChannelSelectorKeys.currentChannel), findsOneWidget);
    expect(find.byKey(ChannelSelectorKeys.channelField), findsOneWidget);
    expect(find.byKey(ChannelSelectorKeys.codeField), findsOneWidget);
    expect(find.byKey(ChannelSelectorKeys.recentSection), findsOneWidget);
    expect(find.byKey(ChannelSelectorKeys.emptyRecent), findsOneWidget);
  });

  group('direct entry validation', () {
    testWidgets('Apply is disabled for invalid/empty input', (tester) async {
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      final applyFinder = find.byKey(ChannelSelectorKeys.applyButton);
      FilledButton applyButton() => tester.widget<FilledButton>(applyFinder);

      expect(applyButton().onPressed, isNull); // both fields empty

      await tester.enterText(
        find.byKey(ChannelSelectorKeys.channelField),
        '100', // out of range -> rejected by input formatter/parse
      );
      await tester.pump();
      expect(applyButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(ChannelSelectorKeys.channelField),
        '7',
      );
      await tester.pump();
      expect(applyButton().onPressed, isNull); // code still empty

      await tester.enterText(find.byKey(ChannelSelectorKeys.codeField), '5');
      await tester.pump();
      expect(applyButton().onPressed, isNotNull);
    });

    testWidgets(
      'rejects 0 and non-numeric without ever dispatching a tune',
      (tester) async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ChannelSelectorKeys.channelField),
          '0',
        );
        await tester.enterText(
          find.byKey(ChannelSelectorKeys.codeField),
          '5',
        );
        await tester.pump();

        final applyButton = tester.widget<FilledButton>(
          find.byKey(ChannelSelectorKeys.applyButton),
        );
        expect(applyButton.onPressed, isNull);
        expect(host.tuneCalls, isEmpty);
      },
    );

    testWidgets('values always render two-digit', (tester) async {
      await seedMemory(const [TunedChannel(channel: 7, privacyCode: 5)]);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(find.text('CH 07 · 05'), findsOneWidget);
    });
  });

  testWidgets('Cancel is a true no-op — no tune dispatched, callback fires', (
    tester,
  ) async {
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(ChannelSelectorKeys.channelField), '7');
    await tester.enterText(find.byKey(ChannelSelectorKeys.codeField), '5');
    await tester.pump();

    await tester.tap(find.byKey(ChannelSelectorKeys.cancelButton));
    await tester.pump();

    expect(host.tuneCalls, isEmpty);
    expect(cancelled, isTrue);
  });

  group('recall section', () {
    testWidgets('shows the existing six-entry recall as a separate, deduplicated, ordered section', (
      tester,
    ) async {
      await seedMemory(const [
        TunedChannel(channel: 7, privacyCode: 5),
        TunedChannel(channel: 12, privacyCode: 0),
      ]);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      expect(
        find.byKey(ChannelSelectorKeys.recentEntry(7, 5)),
        findsOneWidget,
      );
      expect(
        find.byKey(ChannelSelectorKeys.recentEntry(12, 0)),
        findsOneWidget,
      );
      expect(find.byKey(ChannelSelectorKeys.emptyRecent), findsNothing);
    });

    testWidgets('deduplicates a repeated entry, keeping first-seen order', (
      tester,
    ) async {
      await seedMemory(const [
        TunedChannel(channel: 7, privacyCode: 5),
        TunedChannel(channel: 12, privacyCode: 0),
        TunedChannel(channel: 7, privacyCode: 5), // duplicate of the first
      ]);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      // Exactly one card per unique entry, despite the duplicate in memory.
      expect(find.byKey(ChannelSelectorKeys.recentEntry(7, 5)), findsOneWidget);
      expect(find.byKey(ChannelSelectorKeys.recentEntry(12, 0)), findsOneWidget);

      // First-seen order preserved: the (7, 5) card renders above (12, 0).
      final double sevenTop = tester
          .getTopLeft(find.byKey(ChannelSelectorKeys.recentEntry(7, 5)))
          .dy;
      final double twelveTop = tester
          .getTopLeft(find.byKey(ChannelSelectorKeys.recentEntry(12, 0)))
          .dy;
      expect(sevenTop, lessThan(twelveTop));
    });

    testWidgets('tapping a recall entry dispatches tune for that entry', (
      tester,
    ) async {
      await seedMemory(const [TunedChannel(channel: 12, privacyCode: 3)]);
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ChannelSelectorKeys.recentEntry(12, 3)));
      await tester.pump();

      expect(host.tuneCalls, [(12, 3)]);
    });
  });

  group('VT-020/pending-target evidence', () {
    testWidgets('Apply shows progress and blocks competing tune actions', (
      tester,
    ) async {
      host.holdTunes = true;
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ChannelSelectorKeys.channelField),
        '7',
      );
      await tester.enterText(find.byKey(ChannelSelectorKeys.codeField), '5');
      await tester.pump();
      await tester.tap(find.byKey(ChannelSelectorKeys.applyButton));
      await tester.pump();

      expect(find.byKey(ChannelSelectorKeys.progress), findsOneWidget);
      expect(find.byKey(ChannelSelectorKeys.pendingTarget), findsOneWidget);

      // Apply is now disabled — a competing tune action is blocked.
      final applyButton = tester.widget<FilledButton>(
        find.byKey(ChannelSelectorKeys.applyButton),
      );
      expect(applyButton.onPressed, isNull);

      // Resolve so the pending host call doesn't leak into the next test.
      host.completeTune(0, const TuneResult.success());
      await tester.pumpAndSettle();
    });

    testWidgets(
      'the requested target and authoritative current channel are shown distinctly while tuning',
      (tester) async {
        host.holdTunes = true;
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ChannelSelectorKeys.channelField),
          '9',
        );
        await tester.enterText(
          find.byKey(ChannelSelectorKeys.codeField),
          '2',
        );
        await tester.pump();
        await tester.tap(find.byKey(ChannelSelectorKeys.applyButton));
        await tester.pump();

        // Current channel still shows CH 01 · 00 (RadioState's boot default)
        // — never optimistically claims the new channel.
        expect(find.textContaining('CH 01'), findsOneWidget);
        expect(find.textContaining('Requesting'), findsOneWidget);
        expect(find.textContaining('CH 09'), findsOneWidget);

        host.completeTune(0, const TuneResult.success());
        await tester.pumpAndSettle();
      },
    );
  });

  group('UX-FR-030 — TX serialization', () {
    testWidgets(
      'a tune requested during TX is queued and applied only once TX ends, never interrupting it',
      (tester) async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();
        final notifier = container.read(radioStateProvider.notifier)
          ..dispatch(const PowerOn())
          ..dispatch(const BootCompleted())
          ..dispatch(const RequestTransmit())
          ..dispatch(const TransmitGranted());
        await tester.pumpAndSettle();
        expect(
          container.read(radioStateProvider).phase,
          RadioPhase.tx,
        );

        await tester.enterText(
          find.byKey(ChannelSelectorKeys.channelField),
          '4',
        );
        await tester.enterText(
          find.byKey(ChannelSelectorKeys.codeField),
          '1',
        );
        await tester.pump();
        await tester.tap(find.byKey(ChannelSelectorKeys.applyButton));
        await tester.pump();

        // Deferred, not dispatched — TX must not be interrupted.
        expect(host.tuneCalls, isEmpty);
        expect(find.textContaining('Transmission in progress'), findsOneWidget);

        notifier.dispatch(const EndTransmit());
        await tester.pumpAndSettle();

        expect(host.tuneCalls, [(4, 1)]);
      },
    );
  });

  group('recovery policy', () {
    testWidgets(
      'transport failure surfaces feedback with a Retry that re-submits the same target',
      (tester) async {
        host.autoResult = const TuneResult.transportFailure('boom');
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ChannelSelectorKeys.channelField),
          '7',
        );
        await tester.enterText(
          find.byKey(ChannelSelectorKeys.codeField),
          '5',
        );
        await tester.pump();
        await tester.tap(find.byKey(ChannelSelectorKeys.applyButton));
        await tester.pumpAndSettle();

        expect(find.byKey(ChannelSelectorKeys.retryButton), findsOneWidget);
        expect(host.tuneCalls, [(7, 5)]);

        host.autoResult = const TuneResult.success();
        await tester.tap(find.byKey(ChannelSelectorKeys.retryButton));
        await tester.pumpAndSettle();

        expect(host.tuneCalls, [(7, 5), (7, 5)]);
        expect(find.byKey(ChannelSelectorKeys.retryButton), findsNothing);
      },
    );
  });

  group('TASK-057 — accessibility polish', () {
    testWidgets(
      'Cancel and Apply each meet the 48 dp minimum touch target',
      (tester) async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        final Size cancelSize = tester.getSize(
          find.byKey(ChannelSelectorKeys.cancelButton),
        );
        final Size applySize = tester.getSize(
          find.byKey(ChannelSelectorKeys.applyButton),
        );
        expect(cancelSize.height, greaterThanOrEqualTo(48));
        expect(applySize.height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets(
      'the channel and code fields meet the 48 dp minimum touch target',
      (tester) async {
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        final Size channelSize = tester.getSize(
          find.byKey(ChannelSelectorKeys.channelField),
        );
        final Size codeSize = tester.getSize(
          find.byKey(ChannelSelectorKeys.codeField),
        );
        expect(channelSize.height, greaterThanOrEqualTo(48));
        expect(codeSize.height, greaterThanOrEqualTo(48));
      },
    );

    testWidgets(
      'transport-failure feedback is announced as a live region',
      (tester) async {
        host.autoResult = const TuneResult.transportFailure('offline');
        await tester.pumpWidget(build());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(ChannelSelectorKeys.channelField),
          '7',
        );
        await tester.enterText(
          find.byKey(ChannelSelectorKeys.codeField),
          '5',
        );
        await tester.pump();
        await tester.tap(find.byKey(ChannelSelectorKeys.applyButton));
        await tester.pumpAndSettle();

        final Semantics semantics = tester.widget<Semantics>(
          find.descendant(
            of: find.byKey(ChannelSelectorKeys.feedback),
            matching: find.byWidgetPredicate((w) => w is Semantics),
          ).first,
        );
        expect(semantics.properties.liveRegion, isTrue);
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
          await t.pumpWidget(const SizedBox.shrink());
          await t.pumpWidget(build());
          await t.pumpAndSettle();
        });
      },
    );

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(dark)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(build(brightness: Brightness.dark));
      await tester.pumpAndSettle();
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(light)', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(build(brightness: Brightness.light));
      await tester.pumpAndSettle();
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });
  });
}
