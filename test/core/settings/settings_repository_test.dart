import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';

void main() {
  group('SettingsRepository', () {
    late InMemorySettingsStore store;
    late SettingsRepository repository;

    setUp(() {
      store = InMemorySettingsStore();
      repository = SettingsRepository(store);
    });

    test('returns phase-one defaults when nothing is stored', () async {
      final settings = await repository.load();

      expect(settings.totSeconds, 60);
      expect(settings.characterDspIntensity, CharacterDspIntensity.light);
      expect(settings.busyLockout, isTrue);
      expect(settings.forceLocalOnly, isFalse);
      expect(settings.channelMemory, isEmpty);
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
        channelMemory: [TunedChannel(channel: 7, privacyCode: 3)],
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
      await store.write('keryx.settings.v1', '{bad json');

      expect((await repository.load()).totSeconds, 60);
    });
  });
}
