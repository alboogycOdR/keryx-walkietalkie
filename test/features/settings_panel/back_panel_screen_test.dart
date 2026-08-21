import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/settings_panel/settings_panel.dart';

void main() {
  Widget harness(SettingsStore store) {
    return ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: BackPanelScreen()),
    );
  }

  /// Pumps the panel on a tall test surface (every `ListView` section fully
  /// realized, none clipped by the default 800×600 test viewport — same
  /// convention `test/features/face/face_view_test.dart` uses) and settles.
  Future<void> pumpPanel(WidgetTester tester, SettingsStore store) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(store));
    await tester.pumpAndSettle();
  }

  /// Reads back what was actually persisted, independent of the widget
  /// tree — the honest way to assert "round-trips through the repository"
  /// rather than trusting provider state alone.
  Future<KeryxSettings> reload(SettingsStore store) =>
      SettingsRepository(store).load();

  /// A control scoped to one row's [ValueKey], disambiguating identical
  /// option glyphs/labels that recur across rows (e.g. both `+`/`−` and
  /// the roger/DSP `OFF` chips).
  Finder rowChild(String rowKey, Finder matching) =>
      find.descendant(of: find.byKey(ValueKey(rowKey)), matching: matching);

  group('BackPanelScreen — FR-100 back panel / battery-hatch', () {
    testWidgets('renders as the back-panel screen once settings load', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      expect(find.text('BACK PANEL'), findsOneWidget);
      // Every field the Description names is present.
      expect(find.text('SQUELCH'), findsOneWidget);
      expect(find.text('ROGER BEEP'), findsOneWidget);
      expect(find.text('TIME-OUT TIMER'), findsOneWidget);
      expect(find.text('LATCH'), findsOneWidget);
      expect(find.text('BUSY LOCKOUT'), findsOneWidget);
      expect(find.text('CHARACTER DSP'), findsOneWidget);
      expect(find.text('LOCAL ONLY'), findsOneWidget);
      expect(find.text('REGION'), findsOneWidget);
      expect(find.text('DIM'), findsOneWidget);
      expect(find.text('RADIO MODE'), findsOneWidget);
      expect(find.text('RELAY URL'), findsOneWidget);
      expect(find.text('TOKEN URL'), findsOneWidget);
    });

    testWidgets(
      'a corrupt store still renders the loading→data screen, not a crash',
      (tester) async {
        // SettingsRepository.load() is total (never throws) — confirms the
        // panel does not need its own defensive handling for this case, only
        // for a genuinely rejected Future (covered by the error branch below
        // via a store that throws on read).
        final store = InMemorySettingsStore();
        await store.write(SettingsRepository.storageKey, 'not json');
        await pumpPanel(tester, store);

        expect(find.text('BACK PANEL'), findsOneWidget);
        expect(find.text('SQUELCH'), findsOneWidget);
      },
    );

    testWidgets(
      'a rejected load renders the DS §7 in-world failure copy, not a crash',
      (tester) async {
        await tester.pumpWidget(harness(_ThrowingSettingsStore()));
        await tester.pumpAndSettle();

        expect(
          find.text('Settings did not load. Close and reopen the back panel.'),
          findsOneWidget,
        );
      },
    );
  });

  group('squelch — FR-061 round-trip', () {
    testWidgets('+ raises squelchLevel and persists through the repository', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      expect(find.text('5'), findsOneWidget); // squelchLevelDefault

      await tester.tap(rowChild('settings-squelch', find.text('+')));
      await tester.pumpAndSettle();

      expect(find.text('6'), findsOneWidget);
      final persisted = await reload(store);
      expect(persisted.squelchLevel, 6);
    });

    testWidgets('− never drops squelch below its floor', (tester) async {
      final store = InMemorySettingsStore();
      await SettingsRepository(
        store,
      ).save(const KeryxSettings(squelchLevel: KeryxSettings.squelchLevelMin));
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-squelch', find.text('−')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.squelchLevel, KeryxSettings.squelchLevelMin);
    });
  });

  group('time-out timer — FR-023 30–120 s bound', () {
    testWidgets('+ steps by 5 s and persists', (tester) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-tot', find.text('+')));
      await tester.pumpAndSettle();

      expect(find.text('65s'), findsOneWidget);
      final persisted = await reload(store);
      expect(persisted.totSeconds, 65);
    });

    testWidgets('never exceeds the 120 s ceiling', (tester) async {
      final store = InMemorySettingsStore();
      await SettingsRepository(
        store,
      ).save(const KeryxSettings(totSeconds: KeryxSettings.totSecondsMax));
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-tot', find.text('+')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.totSeconds, KeryxSettings.totSecondsMax);
    });
  });

  group('toggles — latch, busy lockout, FR-046 force-LOCAL-only', () {
    testWidgets('LATCH flips and persists', (tester) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(find.byKey(const ValueKey('settings-latch')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.latchMode, isTrue);
    });

    testWidgets('BUSY LOCKOUT flips and persists (default on, per FR-022)', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(find.byKey(const ValueKey('settings-lockout')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.busyLockout, isFalse);
    });

    testWidgets(
      'LOCAL ONLY is exposed (FR-046) and toggling it persists forceLocalOnly',
      (tester) async {
        final store = InMemorySettingsStore();
        await pumpPanel(tester, store);

        expect(find.text('Nothing leaves this network.'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('settings-force-local')));
        await tester.pumpAndSettle();

        final persisted = await reload(store);
        expect(persisted.forceLocalOnly, isTrue);
      },
    );
  });

  group('roger beep / character DSP / dim mode — enum round-trip', () {
    testWidgets('selecting a roger-beep option persists it', (tester) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-roger', find.text('DUAL-TONE')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.rogerBeep, RogerBeepVariant.dualTone);
    });

    testWidgets('selecting a character-DSP option persists it', (tester) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-dsp', find.text('OFF')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.characterDspIntensity, CharacterDspIntensity.off);
    });

    testWidgets('selecting DIM MANUAL persists dimMode', (tester) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-dim', find.text('MANUAL')));
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.dimMode, DimMode.manual);
    });
  });

  group('region — FR-008', () {
    testWidgets('editing and submitting the region field persists it', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.enterText(
        rowChild('settings-region', find.byType(TextField)),
        'za-cpt',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.region, 'za-cpt');
    });

    testWidgets('submitting a blank region is refused, not persisted', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.enterText(
        rowChild('settings-region', find.byType(TextField)),
        '   ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.region, KeryxSettings.defaultRegion);
    });
  });

  group('mode and relay configuration — FR-040 / D2', () {
    testWidgets('selecting LINKED persists the previously-unrendered mode', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.tap(rowChild('settings-mode', find.text('LINKED')));
      await tester.pumpAndSettle();

      expect((await reload(store)).mode, RadioMode.linked);
    });

    testWidgets('relay and advanced token URLs persist on submit', (
      tester,
    ) async {
      final store = InMemorySettingsStore();
      await pumpPanel(tester, store);

      await tester.enterText(
        rowChild('settings-relay-url', find.byType(TextField)),
        'wss://relay.example',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(
        rowChild('settings-token-url', find.byType(TextField)),
        'https://relay.example/token',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final persisted = await reload(store);
      expect(persisted.relayUrl, 'wss://relay.example');
      expect(persisted.tokenServiceUrl, 'https://relay.example/token');
    });
  });

  group('accessibility — FR-106', () {
    testWidgets(
      'every interactive control exposes a TalkBack semantics label',
      (tester) async {
        final store = InMemorySettingsStore();
        await pumpPanel(tester, store);

        // Reads each control's own `Semantics.properties.label` directly off
        // the widget tree, rather than through `find.bySemanticsLabel`'s
        // SemanticsNode lookup — robust regardless of whether a real
        // accessibility tree happens to be attached in this test environment,
        // and it is exactly the property TalkBack reads at runtime.
        bool hasLabel(String label) => find
            .byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.label == label,
            )
            .evaluate()
            .isNotEmpty;

        for (final label in <String>[
          'Increase SQUELCH',
          'Decrease SQUELCH',
          'Increase TIME-OUT TIMER',
          'Decrease TIME-OUT TIMER',
          'LATCH',
          'BUSY LOCKOUT',
          'LOCAL ONLY',
          'ROGER BEEP DUAL-TONE',
          'CHARACTER DSP OFF',
          'DIM MANUAL',
        ]) {
          expect(
            hasLabel(label),
            isTrue,
            reason: 'missing TalkBack label: $label',
          );
        }
      },
    );
  });
}

class _ThrowingSettingsStore implements SettingsStore {
  @override
  Future<String?> read(String key) async {
    throw StateError('storage unavailable');
  }

  @override
  Future<void> write(String key, String value) async {
    throw StateError('storage unavailable');
  }
}
