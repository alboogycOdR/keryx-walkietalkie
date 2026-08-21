import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/bed_mixer.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';

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
      expect(settings.channelMemory, isEmpty);
      expect(settings.dimMode, DimMode.auto);
      expect(settings.mode, RadioMode.auto);
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
        region: 'za-cpt',
        isPro: true,
        channelMemory: [const TunedChannel(channel: 7, privacyCode: 3)],
        dimMode: DimMode.manual,
        mode: RadioMode.local,
        voxSensitivity: 2,
        voxHangTimeMs: 1200,
      );

      await repository.save(expected);
      final actual = await repository.load();

      expect(actual.squelchLevel, expected.squelchLevel);
      expect(actual.rogerBeep, expected.rogerBeep);
      expect(actual.totSeconds, expected.totSeconds);
      expect(actual.busyLockout, expected.busyLockout);
      expect(actual.latchMode, expected.latchMode);
      expect(actual.characterDspIntensity, expected.characterDspIntensity);
      expect(actual.forceLocalOnly, isTrue);
      expect(actual.region, 'za-cpt');
      expect(actual.isPro, isTrue);
      expect(actual.channelMemory, expected.channelMemory);
      expect(actual.dimMode, DimMode.manual);
      expect(actual.mode, RadioMode.local);
      expect(actual.voxSensitivity, 2);
      expect(actual.voxHangTimeMs, 1200);
    });

    test(
      'keeps six most-recent unique tuned channels for quick recall',
      () async {
        for (var channel = 1; channel <= 7; channel++) {
          await repository.rememberChannel(
            TunedChannel(channel: channel, privacyCode: 0),
          );
        }
        await repository.rememberChannel(
          const TunedChannel(channel: 4, privacyCode: 0),
        );

        final memory = (await repository.load()).channelMemory;
        expect(memory, hasLength(6));
        expect(memory.first, const TunedChannel(channel: 4, privacyCode: 0));
        expect(memory.map((entry) => entry.channel), [4, 7, 6, 5, 3, 2]);
      },
    );

    test('rejects an out-of-range TOT before persisting', () async {
      expect(
        () => repository.save(KeryxSettings(totSeconds: 29)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('falls back to defaults when stored data is malformed', () async {
      await store.write(SettingsRepository.storageKey, '{bad json');

      expect((await repository.load()).totSeconds, 60);
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
        expect(settings.mode, RadioMode.auto);
      });
    }

    test('absent storage returns usable defaults', () async {
      final settings = await repository.load();
      expect(settings.totSeconds, KeryxSettings.totSecondsDefault);
      expect(settings.channelMemory, isEmpty);
    });

    test('clamps totSeconds: 999 on read to 120, not defaults', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob(totSeconds: 999)),
      );

      final settings = await repository.load();
      expect(settings.totSeconds, 120);
      expect(settings.region, 'za-cpt');
    });

    test('clamps squelchLevel: 99 on read to 10', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob(squelchLevel: 99)),
      );

      expect((await repository.load()).squelchLevel, 10);
    });

    test('clamps a negative squelchLevel on read to 0', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob(squelchLevel: -3)),
      );

      expect((await repository.load()).squelchLevel, 0);
    });

    test('enforces last-6 channel memory on the read path', () async {
      final blob = _phaseOneBlob()
        ..['channelMemory'] = [
          for (var channel = 1; channel <= 9; channel++)
            {'channel': channel, 'privacyCode': 0},
        ];
      await store.write(SettingsRepository.storageKey, jsonEncode(blob));

      final memory = (await repository.load()).channelMemory;
      expect(memory, hasLength(6));
      expect(memory.map((entry) => entry.channel), [1, 2, 3, 4, 5, 6]);
    });

    test('unknown enum name defaults that field and keeps the rest', () async {
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(_phaseOneBlob()..['rogerBeep'] = 'not-a-variant'),
      );

      final settings = await repository.load();
      expect(settings.rogerBeep, RogerBeepVariant.classic);
      expect(settings.totSeconds, 90);
      expect(settings.region, 'za-cpt');
    });

    test(
      'pre-TASK-030 blob defaults the new keys without dropping others',
      () async {
        await store.write(
          SettingsRepository.storageKey,
          jsonEncode(_legacyBlob()),
        );

        final settings = await repository.load();
        expect(settings.squelchLevel, 8);
        expect(settings.totSeconds, 120);
        expect(settings.forceLocalOnly, isTrue);
        expect(settings.dimMode, DimMode.auto);
        expect(settings.mode, RadioMode.auto);
        expect(settings.voxSensitivity, 5);
        expect(settings.voxHangTimeMs, 500);
      },
    );
  });

  group('squelchNormalized', () {
    test('0 → 0.0 and 10 → 1.0 feed BedMixer.gainsFor', () {
      const closed = KeryxSettings(squelchLevel: 0);
      const open = KeryxSettings(squelchLevel: 10);

      expect(closed.squelchNormalized, 0.0);
      expect(open.squelchNormalized, 1.0);

      expect(
        () => BedMixer.gainsFor(closed.squelchNormalized),
        returnsNormally,
      );
      expect(() => BedMixer.gainsFor(open.squelchNormalized), returnsNormally);
    });
  });

  group('rememberChannel serialization', () {
    test('overlapping calls do not lose an update', () async {
      final store = _SlowStore(InMemorySettingsStore());
      final repository = SettingsRepository(store);
      addTearDown(repository.dispose);

      final calls = <Future<KeryxSettings>>[
        for (var channel = 1; channel <= 6; channel++)
          repository.rememberChannel(
            TunedChannel(channel: channel, privacyCode: 0),
          ),
      ];
      await Future.wait(calls);

      final memory = (await repository.load()).channelMemory;
      expect(memory, hasLength(6));
      expect(memory.map((entry) => entry.channel), [6, 5, 4, 3, 2, 1]);
    });
  });

  group('settingsProvider', () {
    test('re-emits after save without re-reading the repository', () async {
      final store = InMemorySettingsStore();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);

      final seen = <int>[];
      container.listen<AsyncValue<KeryxSettings>>(settingsProvider, (
        previous,
        next,
      ) {
        final value = next.asData?.value;
        if (value != null) seen.add(value.totSeconds);
      }, fireImmediately: true);

      await container
          .read(settingsRepositoryProvider)
          .save(const KeryxSettings(totSeconds: 90, region: 'za-cpt'));

      expect(seen, contains(90));
      expect(container.read(settingsProvider).asData!.value.totSeconds, 90);
      expect(container.read(settingsProvider).asData!.value.region, 'za-cpt');
    });

    test('re-emits after rememberChannel', () async {
      final store = InMemorySettingsStore();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await container.read(settingsProvider.future);

      List<TunedChannel>? latestMemory;
      container.listen<AsyncValue<KeryxSettings>>(settingsProvider, (
        previous,
        next,
      ) {
        latestMemory = next.asData?.value.channelMemory;
      });

      await container
          .read(settingsProvider.notifier)
          .rememberChannel(const TunedChannel(channel: 12, privacyCode: 4));

      expect(latestMemory, [const TunedChannel(channel: 12, privacyCode: 4)]);
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

/// Forces overlapping read-modify-write windows so a missing lock fails.
class _SlowStore implements SettingsStore {
  _SlowStore(this._inner);

  final SettingsStore _inner;

  @override
  Future<String?> read(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 8));
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 8));
    await _inner.write(key, value);
  }
}
