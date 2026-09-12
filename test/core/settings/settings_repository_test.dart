import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/bed_mixer.dart';
import 'package:keryx/core/settings/settings_repository.dart';


void main() {
  group('SettingsRepository', () {
    late InMemorySettingsStore store;
    late SettingsRepository repository;

    setUp(() {
      store = InMemorySettingsStore();
      repository = SettingsRepository(store);
    });

    tearDown(() => repository.dispose());

    test('returns phase-one defaults when nothing is stored', () async {
      final settings = await repository.load();

      expect(settings.totSeconds, 60);
      expect(settings.characterDspIntensity, CharacterDspIntensity.light);
      expect(settings.busyLockout, isTrue);
      expect(settings.forceLocalOnly, isFalse);
      expect(settings.dimMode, DimMode.auto);
      expect(settings.voxSensitivity, 5);
      expect(settings.voxHangTimeMs, 500);
      expect(settings.squelchLevel, 5);
    });

    test('round-trips every local-only setting through the store', () async {
      final expected = KeryxSettings(
        squelchLevel: 8,
        rogerBeep: RogerBeepVariant.dualTone,
        totSeconds: 120,
        busyLockout: false,
        latchMode: true,
        characterDspIntensity: CharacterDspIntensity.full,
        forceLocalOnly: true,
        isPro: true,
        dimMode: DimMode.manual,
        voxSensitivity: 2,
        voxHangTimeMs: 1200);

      await repository.save(expected);
      final actual = await repository.load();

      expect(actual.squelchLevel, expected.squelchLevel);
      expect(actual.rogerBeep, expected.rogerBeep);
      expect(actual.totSeconds, expected.totSeconds);
      expect(actual.busyLockout, expected.busyLockout);
      expect(actual.latchMode, expected.latchMode);
      expect(actual.characterDspIntensity, expected.characterDspIntensity);
      expect(actual.forceLocalOnly, isTrue);
      expect(actual.isPro, isTrue);
      expect(actual.dimMode, DimMode.manual);
      expect(actual.voxSensitivity, 2);
      expect(actual.voxHangTimeMs, 1200);
      expect(actual.relayUrl, KeryxSettings.relayUrlDefault);
      expect(actual.tokenServiceUrl, KeryxSettings.tokenServiceUrlDefault);
    });

    test(
      'normalizes invalid endpoints and derives the Caddy token route',
      () async {
        final saved = await repository.save(
          const KeryxSettings(
            relayUrl: ' https://not-a-websocket.example ',
            tokenServiceUrl: 'http://not-secure.example/token'));

        expect(saved.relayUrl, KeryxSettings.relayUrlDefault);
        expect(saved.tokenServiceUrl, KeryxSettings.tokenServiceUrlDefault);

        final linked = await repository.save(
          const KeryxSettings(relayUrl: 'wss://relay.example:7880/livekit'));
        expect(linked.relayUrl, 'wss://relay.example:7880/livekit');
        expect(linked.tokenServiceUrl, KeryxSettings.tokenServiceUrlDefault);
        expect(
          linked.resolvedTokenServiceUrl,
          KeryxSettings.tokenServiceUrlDefault.isNotEmpty
              ? KeryxSettings.tokenServiceUrlDefault
              : 'https://relay.example:7880/token');
      });

    test('rejects an out-of-range TOT before persisting', () async {
      expect(
        () => repository.save(KeryxSettings(totSeconds: 29)),
        throwsA(isA<AssertionError>()));
    });

    test('falls back to defaults when stored data is malformed', () async {
      await store.write(SettingsRepository.storageKey, '{bad json');

      expect((await repository.load()).totSeconds, 60);
    });

    // v2 (Technical §7, TASK-088): additive coverage for
    // preferDirectOnWifi/messageRetentionDays — every test above is
    // unmodified.
    test('defaults preferDirectOnWifi and messageRetentionDays', () async {
      final settings = await repository.load();
      expect(settings.preferDirectOnWifi, isTrue);
      expect(settings.messageRetentionDays, 7);
    });

    test(
      'round-trips preferDirectOnWifi/messageRetentionDays through the store',
      () async {
        await repository.save(
          const KeryxSettings(
            preferDirectOnWifi: false,
            messageRetentionDays: 30));
        final actual = await repository.load();
        expect(actual.preferDirectOnWifi, isFalse);
        expect(actual.messageRetentionDays, 30);
      });

    test(
      'a persisted value with no v2 keys defaults them rather than failing',
      () async {
        await store.write(
          SettingsRepository.storageKey,
          jsonEncode({'totSeconds': 90}));
        final settings = await repository.load();
        expect(settings.totSeconds, 90);
        expect(settings.preferDirectOnWifi, isTrue);
        expect(settings.messageRetentionDays, 7);
      });

    test('clamps an out-of-range messageRetentionDays on read', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode({'messageRetentionDays': 9999}));
      final settings = await repository.load();
      expect(
        settings.messageRetentionDays,
        KeryxSettings.messageRetentionDaysMax);
    });
  });

  group('load() is total', () {
    late InMemorySettingsStore store;
    late SettingsRepository repository;

    setUp(() {
      store = InMemorySettingsStore();
      repository = SettingsRepository(store);
    });

    tearDown(() => repository.dispose());

    const table = <String, String>{
      'array': '[]',
      'number': '5',
      'string': '"hello"',
      'null': 'null',
      'malformed': '{bad json',
      'empty': '',
    };

    for (final entry in table.entries) {
      test('never throws for ${entry.key} blob', () async {
        await store.write(SettingsRepository.storageKey, entry.value);
        final settings = await repository.load();
        expect(settings.totSeconds, 60);
        expect(settings.squelchLevel, 5);
      });
    }

    test('absent storage returns usable defaults', () async {
      final settings = await repository.load();
      expect(settings.totSeconds, KeryxSettings.totSecondsDefault);
    });

    test('clamps totSeconds: 999 on read to 120, not defaults', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob(totSeconds: 999)));

      final settings = await repository.load();
      expect(settings.totSeconds, 120);
    });

    test('clamps squelchLevel: 99 on read to 10', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob(squelchLevel: 99)));

      expect((await repository.load()).squelchLevel, 10);
    });

    test('clamps a negative squelchLevel on read to 0', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob(squelchLevel: -3)));

      expect((await repository.load()).squelchLevel, 0);
    });

    test('unknown enum name defaults that field and keeps the rest', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob()..['rogerBeep'] = 'not-a-variant'));

      final settings = await repository.load();
      expect(settings.rogerBeep, RogerBeepVariant.classic);
      expect(settings.totSeconds, 90);
    });

    test(
      'pre-TASK-030 blob defaults the new keys without dropping others',
      () async {
        await store.write(
          SettingsRepository.storageKey,
          jsonEncode(_legacyBlob()));

        final settings = await repository.load();
        expect(settings.squelchLevel, 8);
        expect(settings.totSeconds, 120);
        expect(settings.forceLocalOnly, isTrue);
        expect(settings.dimMode, DimMode.auto);
        expect(settings.voxSensitivity, 5);
        expect(settings.voxHangTimeMs, 500);
      });

    test(
      'blank, whitespace, and non-wss endpoint keys fall back safely',
      () async {
        await store.write(
          SettingsRepository.storageKey,
          jsonEncode(
            _phaseOneBlob()
              ..['relayUrl'] = '   '
              ..['tokenServiceUrl'] = 'wss://wrong-scheme.example/token'));

        final settings = await repository.load();
        expect(settings.relayUrl, KeryxSettings.relayUrlDefault);
        expect(settings.tokenServiceUrl, KeryxSettings.tokenServiceUrlDefault);
      });

    test(
      'a non-empty persisted endpoint overrides the build default',
      () async {
        await store.write(
          SettingsRepository.storageKey,
          jsonEncode(
            _phaseOneBlob()
              ..['relayUrl'] = 'wss://saved.example'
              ..['tokenServiceUrl'] = 'https://saved.example/token'));

        final settings = await repository.load();
        expect(settings.relayUrl, 'wss://saved.example');
        expect(settings.tokenServiceUrl, 'https://saved.example/token');
      });
  });

  group('squelchNormalized', () {
    test('0 → 0.0 and 10 → 1.0 feed BedMixer.gainsFor', () {
      const closed = KeryxSettings(squelchLevel: 0);
      const open = KeryxSettings(squelchLevel: 10);

      expect(closed.squelchNormalized, 0.0);
      expect(open.squelchNormalized, 1.0);

      expect(
        () => BedMixer.gainsFor(closed.squelchNormalized),
        returnsNormally);
      expect(() => BedMixer.gainsFor(open.squelchNormalized), returnsNormally);
    });
  });

  group('settingsProvider', () {
    test('re-emits after save without re-reading the repository', () async {
      final store = InMemorySettingsStore();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)]);
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);

      final seen = <int>[];
      container.listen<AsyncValue<KeryxSettings>>(settingsProvider, (
        previous,
        next) {
        final value = next.asData?.value;
        if (value != null) seen.add(value.totSeconds);
      }, fireImmediately: true);

      await container
          .read(settingsRepositoryProvider)
          .save(const KeryxSettings(totSeconds: 90));

      expect(seen, contains(90));
      expect(container.read(settingsProvider).asData!.value.totSeconds, 90);
    });
  });
}

Map<String, Object?> _phaseOneBlob({
  int totSeconds = 90,
  int squelchLevel = 8,
}) {
  return {
    'squelchLevel': squelchLevel,
    'rogerBeep': 'dualTone',
    'totSeconds': totSeconds,
    'busyLockout': false,
    'latchMode': true,
    'characterDspIntensity': 'full',
    'forceLocalOnly': true,
    'region': 'za-cpt',
    'isPro': true,
    'channelMemory': [
      {'channel': 7, 'privacyCode': 3},
    ],
  };
}

Map<String, Object?> _legacyBlob() => {
  'squelchLevel': 8,
  'rogerBeep': 'dualTone',
  'totSeconds': 120,
  'busyLockout': false,
  'latchMode': true,
  'characterDspIntensity': 'full',
  'forceLocalOnly': true,
  'region': 'za-cpt',
  'isPro': true,
  'channelMemory': [
    {'channel': 7, 'privacyCode': 3},
  ],
};
