import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/settings/settings.dart';

import '../../core/identity/memory_identity_store.dart';
import '../talk/a11y_matrix_support.dart';
import 'fake_radio_host.dart';

class SeededRadioStateController extends RadioStateController {
  SeededRadioStateController(this._seed);

  final RadioState _seed;

  @override
  RadioState build() => _seed;

  void seed(RadioState next) => state = next;
}

Finder rowChild(Key rowKey, Finder matching) =>
    find.descendant(of: find.byKey(rowKey), matching: matching);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ReconstructingFakeHost host;
  late InMemorySettingsStore store;
  late MemoryIdentityStore identityStore;
  late SeededRadioStateController radio;

  Future<void> pumpSettings(
    WidgetTester tester, {
    KeryxSettings settings = const KeryxSettings(),
    RadioState radioState = const RadioState(
      phase: RadioPhase.idle),
    SettingsConfirm? confirm,
    bool useProductionConfirm = false,
    Size surface = const Size(800, 3600),
    Brightness brightness = Brightness.dark,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    host = ReconstructingFakeHost(settings);
    store = InMemorySettingsStore();
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(settings.toJson()));
    identityStore = MemoryIdentityStore(<String, String>{
      IdentityRepository.uuidKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    radio = SeededRadioStateController(radioState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(store),
          radioStateProvider.overrideWith(() => radio),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: SettingsScreen(
            identityRepository: IdentityRepository(identityStore),
            recoveryPhraseStore: identityStore,
            confirm: useProductionConfirm
                ? null
                : confirm ??
                      ({required String title, required String body}) async =>
                          true))));
    await tester.pumpAndSettle();
  }

  testWidgets('six sections and their v2 controls render (Design §2.6)', (
    tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(SettingsKeys.radioSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.audioSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.connectivitySection), findsOneWidget);
    expect(find.byKey(SettingsKeys.identitySection), findsOneWidget);
    expect(find.byKey(SettingsKeys.messagesSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.appearanceSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.aboutSection), findsOneWidget);

    expect(find.text('Squelch'), findsOneWidget);
    expect(find.text('Roger beep'), findsOneWidget);
    expect(find.text('Time-out timer'), findsOneWidget);
    expect(find.text('Latch'), findsOneWidget);
    expect(find.text('Busy lockout'), findsOneWidget);
    expect(find.text('Character DSP'), findsOneWidget);
    expect(find.text('Dim'), findsOneWidget);
    expect(find.text('This network only'), findsOneWidget);
    expect(find.text('Relay URL'), findsOneWidget);
    expect(find.text('Token URL'), findsOneWidget);
    expect(find.text('Prefer direct on Wi-Fi'), findsOneWidget);
    expect(find.text('Callsign'), findsOneWidget);
    expect(find.text('Show recovery phrase'), findsOneWidget);
    expect(find.text('Restore from phrase'), findsOneWidget);
    expect(find.text('Message retention'), findsOneWidget);
    expect(find.text('Active path'), findsOneWidget);
    expect(find.text('Audio routing'), findsOneWidget);
    expect(find.text('Device default'), findsOneWidget);
    expect(find.text('BRAVO-7'), findsOneWidget);
    expect(find.text(SettingsCopy.appVersion), findsWidgets);

    // Removed by TASK-093 (Design §2.6/§2.7): no Radio mode or Region rows.
    expect(find.text('Radio mode'), findsNothing);
    expect(find.text('Region'), findsNothing);
  });

  testWidgets(
    'session-affecting rows carry reconnect copy; appearance does not',
    (tester) async {
      await pumpSettings(tester);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.tot),
          matching: find.text(SettingsCopy.reconnectsRadio)),
        findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.forceLocal),
          matching: find.text(SettingsCopy.reconnectsRadio)),
        findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.dim),
          matching: find.text(SettingsCopy.reconnectsRadio)),
        findsNothing);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.theme),
          matching: find.text(SettingsCopy.reconnectsRadio)),
        findsNothing);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.squelch),
          matching: find.text(SettingsCopy.reconnectsRadio)),
        findsNothing);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.preferDirect),
          matching: find.text(SettingsCopy.reconnectsRadio)),
        findsNothing,
        reason: 'Prefer direct on Wi-Fi is not marked sessionAffecting');
    });

  testWidgets('squelch persists without reconstructing the session', (
    tester) async {
    await pumpSettings(tester);
    await tester.tap(rowChild(SettingsKeys.squelch, find.byIcon(Icons.add)));
    await tester.pumpAndSettle();
    final KeryxSettings persisted = await SettingsRepository(store).load();
    expect(persisted.squelchLevel, 6);
    expect(host.reconstructions, 0);
    expect(host.applySettingsCalls, isNotEmpty);
  });

  testWidgets(
    'This network only, when on, names contacts and presence as blocked',
    (tester) async {
      await pumpSettings(
        tester,
        settings: const KeryxSettings(forceLocalOnly: true),
      );
      expect(find.byKey(SettingsKeys.forceLocalNote), findsOneWidget);
      expect(find.text(SettingsCopy.forceLocalBlocksWan), findsOneWidget);
      expect(
        SettingsCopy.forceLocalBlocksWan.toLowerCase(),
        contains('contact'),
      );
      expect(
        SettingsCopy.forceLocalBlocksWan.toLowerCase(),
        contains('presence'),
      );
    },
  );

  testWidgets('a session-affecting toggle (Local only) shows confirmation; '
      'cancel does not apply', (tester) async {
    await pumpSettings(
      tester,
      confirm: ({required String title, required String body}) async => false);
    await tester.tap(rowChild(SettingsKeys.forceLocal, find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(host.applySettingsCalls, isEmpty);
    expect(host.reconstructions, 0);
  });

  testWidgets('a session-affecting toggle confirm reconstructs once with '
      'the new value', (tester) async {
    await pumpSettings(tester);
    await tester.tap(rowChild(SettingsKeys.forceLocal, find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(host.reconstructions, 1);
    expect(host.applied.forceLocalOnly, isTrue);
    expect(host.disposedSessions, hasLength(1));
    expect(host.disposedSessions.single.changes.isClosed, isTrue);
  });

  testWidgets('real confirmation dialog is cancellable', (tester) async {
    await pumpSettings(tester, useProductionConfirm: true);
    await tester.tap(rowChild(SettingsKeys.forceLocal, find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsKeys.confirmDialog), findsOneWidget);
    expect(find.text(SettingsCopy.confirmBody), findsOneWidget);
    await tester.tap(find.byKey(SettingsKeys.confirmCancel));
    await tester.pumpAndSettle();
    expect(host.applySettingsCalls, isEmpty);
  });

  testWidgets('TX defers a session-affecting apply until idle', (tester) async {
    await pumpSettings(
      tester,
      radioState: const RadioState(phase: RadioPhase.tx));
    await tester.tap(rowChild(SettingsKeys.forceLocal, find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(host.applySettingsCalls, isEmpty);
    expect(find.byKey(SettingsKeys.deferredBanner), findsOneWidget);

    radio.seed(const RadioState(phase: RadioPhase.idle));
    await tester.pumpAndSettle();
    expect(host.reconstructions, 1);
    expect(host.applied.forceLocalOnly, isTrue);
    expect(find.byKey(SettingsKeys.deferredBanner), findsNothing);
  });

  testWidgets(
    'unresolved effective route is Connecting, never AUTO (Technical §7)',
    (tester) async {
      await pumpSettings(
        tester,
        settings: const KeryxSettings(),
        radioState: const RadioState(
          phase: RadioPhase.idle));
      expect(
        rowChild(SettingsKeys.effectiveRoute, find.text('Connecting')),
        findsOneWidget);
      expect(
        rowChild(SettingsKeys.effectiveRoute, find.text('AUTO')),
        findsNothing);
    });

  testWidgets('audio copy never substitutes generic messaging sounds', (
    tester) async {
    await pumpSettings(tester);
    expect(find.textContaining('notification'), findsNothing);
    expect(find.textContaining('ringtone'), findsNothing);
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.text('Roger beep'), findsOneWidget);
    expect(find.text('Device default'), findsOneWidget);
  });

  testWidgets('About shows version and no internal service names', (
    tester) async {
    await pumpSettings(tester);
    expect(find.text(SettingsCopy.appVersion), findsWidgets);
    expect(find.textContaining('FloorEngine'), findsNothing);
    expect(find.textContaining('RadioSession'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('livekit'), findsNothing);
  });

  testWidgets('invalid callsign is refused and not persisted', (tester) async {
    await pumpSettings(tester);
    await tester.enterText(
      find.descendant(
        of: find.byKey(SettingsKeys.callsign),
        matching: find.byType(TextField)),
      'no spaces allowed!!');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(SettingsCopy.callsignInvalid), findsOneWidget);
    final DeviceIdentity identity = await IdentityRepository(
      identityStore).loadOrCreate();
    expect(identity.callsign.value, 'BRAVO-7');
  });

  group('TASK-093 — Identity: show recovery phrase / restore', () {
    testWidgets(
      'Show recovery phrase with no saved phrase shows the unavailable '
      'snack bar rather than a broken screen',
      (tester) async {
        await pumpSettings(tester);
        await tester.tap(
          rowChild(SettingsKeys.showRecoveryPhrase, find.text('Show')));
        await tester.pumpAndSettle();
        expect(
          find.text(SettingsCopy.showRecoveryPhraseUnavailable),
          findsOneWidget);
      });

    testWidgets(
      'Show recovery phrase with a saved phrase requires confirmation, '
      'then displays the 12 words',
      (tester) async {
        await pumpSettings(tester);
        await identityStore.write(
          'keryx.v2.recovery_phrase_words',
          jsonEncode(List<String>.generate(12, (i) => 'word$i')));

        await tester.tap(
          rowChild(SettingsKeys.showRecoveryPhrase, find.text('Show')));
        await tester.pumpAndSettle();
        expect(find.byKey(SettingsKeys.recoveryPhraseGate), findsOneWidget);
        expect(
          find.text(SettingsCopy.recoveryPhraseConfirmBody),
          findsOneWidget);

        await tester.tap(
          rowChild(
            SettingsKeys.recoveryPhraseGate,
            find.text(SettingsCopy.recoveryPhraseConfirmShow)));
        await tester.pumpAndSettle();
        expect(find.textContaining('word0'), findsOneWidget);
        expect(find.textContaining('word11'), findsOneWidget);
      });

    testWidgets(
      'Restore from phrase requires confirmation before navigating away',
      (tester) async {
        await pumpSettings(tester);
        await tester.tap(
          rowChild(SettingsKeys.restoreFromPhrase, find.text('Restore')));
        await tester.pumpAndSettle();
        expect(find.byKey(SettingsKeys.restoreConfirm), findsOneWidget);
        expect(find.text(SettingsCopy.restoreConfirmBody), findsOneWidget);

        await tester.tap(find.text(SettingsCopy.confirmCancel));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
      });
  });

  group('TASK-093 — Messages section', () {
    testWidgets('shows the retention value and the "used from v2.1" label '
        '(Design §2.7)', (tester) async {
      await pumpSettings(
        tester,
        settings: const KeryxSettings(messageRetentionDays: 30));
      expect(
        rowChild(SettingsKeys.messageRetention, find.text('30 d')),
        findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(SettingsKeys.messagesSection),
          matching: find.textContaining('v2.1')),
        findsWidgets);
    });
  });

  group('TASK-093 — Connectivity: Prefer direct on Wi-Fi', () {
    testWidgets('toggling does not reconstruct the session (not '
        'sessionAffecting)', (tester) async {
      await pumpSettings(tester);
      await tester.tap(rowChild(SettingsKeys.preferDirect, find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(host.reconstructions, 0);
      expect(host.applySettingsCalls, isNotEmpty);
      final KeryxSettings persisted = await SettingsRepository(store).load();
      expect(
        persisted.preferDirectOnWifi,
        isFalse,
        reason: 'preferDirectOnWifi defaults to true (Technical §7)');
    });
  });

  testWidgets('theme save does not drop a legacy settings fixture', (
    tester) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Map<String, Object?> legacy = <String, Object?>{
      'squelchLevel': 8,
      'rogerBeep': 'dualTone',
      'totSeconds': 120,
      'busyLockout': false,
      'latchMode': true,
      'characterDspIntensity': 'full',
      'forceLocalOnly': true,
      'region': 'za-cpt',
      'isPro': true,
      'channelMemory': <Map<String, int>>[
        <String, int>{'channel': 7, 'privacyCode': 3},
      ],
      'relayUrl': 'wss://old.example/relay',
      'tokenServiceUrl': 'https://old.example/token',
    };
    final KeryxSettings loaded = KeryxSettings.fromJson(legacy);
    host = ReconstructingFakeHost(loaded);
    store = InMemorySettingsStore();
    await store.write(SettingsRepository.storageKey, jsonEncode(legacy));
    identityStore = MemoryIdentityStore(<String, String>{
      IdentityRepository.uuidKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    radio = SeededRadioStateController(
      const RadioState(phase: RadioPhase.idle));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(store),
          radioStateProvider.overrideWith(() => radio),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(),
          home: SettingsScreen(
            identityRepository: IdentityRepository(identityStore),
            confirm: ({required String title, required String body}) async =>
                true))));
    await tester.pumpAndSettle();

    await tester.tap(rowChild(SettingsKeys.theme, find.text('Light')));
    await tester.pumpAndSettle();
    await tester.tap(rowChild(SettingsKeys.dim, find.text('Manual')));
    await tester.pumpAndSettle();

    final KeryxSettings persisted = await SettingsRepository(store).load();
    expect(persisted.squelchLevel, 8);
    expect(persisted.latchMode, isTrue);
    expect(persisted.forceLocalOnly, isTrue);
    expect(persisted.relayUrl, 'wss://old.example/relay');
    expect(persisted.dimMode, DimMode.manual);
    expect(host.reconstructions, 0);
    expect(
      await AppearanceStore(store).load(),
      const AppearancePreference(theme: AppearanceTheme.light));
  });

  group('TASK-057 — accessibility polish', () {
    testWidgets(
      'the callsign text field carries an explicit accessible label, not '
      'just a visually-adjacent one',
      (tester) async {
        await pumpSettings(tester);
        final Semantics semantics = tester.widget<Semantics>(
          find
              .descendant(
                of: find.byKey(SettingsKeys.callsign),
                matching: find.byWidgetPredicate((w) => w is Semantics))
              .first);
        expect(semantics.properties.label, contains('Callsign'));
      });

    testWidgets(
      'the squelch stepper value announces which setting it belongs to',
      (tester) async {
        await pumpSettings(tester);
        final Semantics semantics = tester.widget<Semantics>(
          find.descendant(
            of: find.byKey(SettingsKeys.squelch),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  (w.properties.label ?? '').contains('Squelch,'))));
        expect(semantics.properties.label, contains('Squelch,'));
      });
  });

  group('TASK-057 round 2 — responsive matrix + rendered guidelines', () {
    testWidgets('renders without exception across the full responsive matrix '
        '(320 lp, larger phone, landscape, text scale 2.0)', (tester) async {
      await expectResponsiveMatrix(tester, (t, size) async {
        await t.pumpWidget(const SizedBox.shrink());
        await pumpSettings(t, surface: size);
      });
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(dark)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester, brightness: Brightness.dark);
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });

    testWidgets('meets WCAG AA rendered contrast and 48dp tap targets '
        '(light)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester, brightness: Brightness.light);
      await expectRenderedContrast(tester);
      await expectTapTargets(tester);
      handle.dispose();
    });
  });
}
