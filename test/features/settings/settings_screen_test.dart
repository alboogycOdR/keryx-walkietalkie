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
      phase: RadioPhase.idle,
      mode: RadioMode.local,
    ),
    SettingsConfirm? confirm,
    bool useProductionConfirm = false,
  }) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    host = ReconstructingFakeHost(settings);
    store = InMemorySettingsStore();
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(settings.toJson()),
    );
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
          theme: keryxUxThemeData(),
          home: SettingsScreen(
            identityRepository: IdentityRepository(identityStore),
            confirm: useProductionConfirm
                ? null
                : confirm ??
                    ({required String title, required String body}) async =>
                        true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('six sections and every legacy control render', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byKey(SettingsKeys.radioSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.audioSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.connectivitySection), findsOneWidget);
    expect(find.byKey(SettingsKeys.identitySection), findsOneWidget);
    expect(find.byKey(SettingsKeys.appearanceSection), findsOneWidget);
    expect(find.byKey(SettingsKeys.aboutSection), findsOneWidget);

    expect(find.text('Squelch'), findsOneWidget);
    expect(find.text('Roger beep'), findsOneWidget);
    expect(find.text('Time-out timer'), findsOneWidget);
    expect(find.text('Latch'), findsOneWidget);
    expect(find.text('Busy lockout'), findsOneWidget);
    expect(find.text('Character DSP'), findsOneWidget);
    expect(find.text('Dim'), findsOneWidget);
    expect(find.text('Radio mode'), findsOneWidget);
    expect(find.text('Local only'), findsOneWidget);
    expect(find.text('Region'), findsOneWidget);
    expect(find.text('Relay URL'), findsOneWidget);
    expect(find.text('Token URL'), findsOneWidget);
    expect(find.text('Callsign'), findsOneWidget);
    expect(find.text('Effective route'), findsOneWidget);
    expect(find.text('Audio routing'), findsOneWidget);
    expect(find.text('Device default'), findsOneWidget);
    expect(find.text('BRAVO-7'), findsOneWidget);
    expect(find.text(SettingsCopy.appVersion), findsWidgets);
  });

  testWidgets('session-affecting rows carry reconnect copy; appearance does not', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(
      find.descendant(
        of: find.byKey(SettingsKeys.tot),
        matching: find.text(SettingsCopy.reconnectsRadio),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SettingsKeys.mode),
        matching: find.text(SettingsCopy.reconnectsRadio),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(SettingsKeys.dim),
        matching: find.text(SettingsCopy.reconnectsRadio),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(SettingsKeys.theme),
        matching: find.text(SettingsCopy.reconnectsRadio),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(SettingsKeys.squelch),
        matching: find.text(SettingsCopy.reconnectsRadio),
      ),
      findsNothing,
    );
  });

  testWidgets('squelch persists without reconstructing the session', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.tap(
      rowChild(SettingsKeys.squelch, find.byIcon(Icons.add)),
    );
    await tester.pumpAndSettle();
    final KeryxSettings persisted = await SettingsRepository(store).load();
    expect(persisted.squelchLevel, 6);
    expect(host.reconstructions, 0);
    expect(host.applySettingsCalls, isNotEmpty);
  });

  testWidgets('mode change shows confirmation; cancel does not apply', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      confirm: ({required String title, required String body}) async => false,
    );
    await tester.tap(rowChild(SettingsKeys.mode, find.text('Linked')));
    await tester.pumpAndSettle();
    expect(host.applySettingsCalls, isEmpty);
    expect(host.reconstructions, 0);
  });

  testWidgets('mode change confirm reconstructs once with the new mode', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.tap(rowChild(SettingsKeys.mode, find.text('Linked')));
    await tester.pumpAndSettle();
    expect(host.reconstructions, 1);
    expect(host.applied.mode, RadioMode.linked);
    expect(host.disposedSessions, hasLength(1));
    expect(host.disposedSessions.single.changes.isClosed, isTrue);
  });

  testWidgets('real confirmation dialog is cancellable', (tester) async {
    await pumpSettings(tester, useProductionConfirm: true);
    await tester.tap(rowChild(SettingsKeys.mode, find.text('Linked')));
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
      radioState: const RadioState(phase: RadioPhase.tx, mode: RadioMode.local),
    );
    await tester.tap(rowChild(SettingsKeys.mode, find.text('Linked')));
    await tester.pumpAndSettle();
    expect(host.applySettingsCalls, isEmpty);
    expect(find.byKey(SettingsKeys.deferredBanner), findsOneWidget);

    radio.seed(
      const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
    );
    await tester.pumpAndSettle();
    expect(host.reconstructions, 1);
    expect(host.applied.mode, RadioMode.linked);
    expect(find.byKey(SettingsKeys.deferredBanner), findsNothing);
  });

  testWidgets(
    'VT-022: configured, effective and Local only are distinct; force-LOCAL blocks WAN',
    (tester) async {
      await pumpSettings(
        tester,
        settings: const KeryxSettings(
          mode: RadioMode.auto,
          forceLocalOnly: true,
        ),
        radioState: const RadioState(
          phase: RadioPhase.idle,
          mode: RadioMode.local,
        ),
      );
      expect(
        rowChild(SettingsKeys.mode, find.text('Auto')),
        findsOneWidget,
      );
      expect(
        rowChild(SettingsKeys.effectiveRoute, find.text('Local')),
        findsOneWidget,
      );
      expect(find.byKey(SettingsKeys.forceLocalNote), findsOneWidget);

      await tester.tap(rowChild(SettingsKeys.mode, find.text('Linked')));
      await tester.pumpAndSettle();
      expect(host.joinEventCalls, isEmpty);
      expect(host.methodLog, isNot(contains('joinEvent')));
      expect(host.applied.forceLocalOnly, isTrue);
      expect(host.applied.mode, RadioMode.linked);
    },
  );

  testWidgets('audio copy never substitutes generic messaging sounds', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.textContaining('notification'), findsNothing);
    expect(find.textContaining('ringtone'), findsNothing);
    expect(find.textContaining('SMS'), findsNothing);
    expect(find.text('Roger beep'), findsOneWidget);
    expect(find.text('Device default'), findsOneWidget);
  });

  testWidgets('About shows version and no internal service names', (
    tester,
  ) async {
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
        matching: find.byType(TextField),
      ),
      'no spaces allowed!!',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text(SettingsCopy.callsignInvalid), findsOneWidget);
    final DeviceIdentity identity =
        await IdentityRepository(identityStore).loadOrCreate();
    expect(identity.callsign.value, 'BRAVO-7');
  });

  testWidgets('theme save does not drop a legacy settings fixture', (
    tester,
  ) async {
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
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(legacy),
    );
    identityStore = MemoryIdentityStore(<String, String>{
      IdentityRepository.uuidKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    radio = SeededRadioStateController(
      const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
    );

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
                true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(rowChild(SettingsKeys.theme, find.text('Light')));
    await tester.pumpAndSettle();
    await tester.tap(rowChild(SettingsKeys.dim, find.text('Manual')));
    await tester.pumpAndSettle();

    final KeryxSettings persisted = await SettingsRepository(store).load();
    expect(persisted.squelchLevel, 8);
    expect(persisted.region, 'za-cpt');
    expect(persisted.latchMode, isTrue);
    expect(persisted.forceLocalOnly, isTrue);
    expect(persisted.relayUrl, 'wss://old.example/relay');
    expect(persisted.dimMode, DimMode.manual);
    expect(host.reconstructions, 0);
    expect(
      await AppearanceStore(store).load(),
      const AppearancePreference(theme: AppearanceTheme.light),
    );
  });

  group('TASK-057 — accessibility polish', () {
    testWidgets(
      'the callsign text field carries an explicit accessible label, not '
      'just a visually-adjacent one',
      (tester) async {
        await pumpSettings(tester);
        final Semantics semantics = tester.widget<Semantics>(
          find.descendant(
            of: find.byKey(SettingsKeys.callsign),
            matching: find.byWidgetPredicate((w) => w is Semantics),
          ).first,
        );
        expect(semantics.properties.label, contains('Callsign'));
      },
    );

    testWidgets(
      'the squelch stepper value announces which setting it belongs to',
      (tester) async {
        await pumpSettings(tester);
        final Semantics semantics = tester.widget<Semantics>(
          find.descendant(
            of: find.byKey(SettingsKeys.squelch),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && (w.properties.label ?? '').contains('Squelch,'),
            ),
          ),
        );
        expect(semantics.properties.label, contains('Squelch,'));
      },
    );
  });
}
