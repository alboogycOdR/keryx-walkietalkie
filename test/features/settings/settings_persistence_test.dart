import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';

import 'package:keryx/features/settings/settings.dart';

import '../../core/identity/memory_identity_store.dart';

/// Pre-redesign blob: no dimMode / mode / vox / URL keys. VT-005.
Map<String, Object?> legacySettingsBlob() => <String, Object?>{
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

void main() {
  test('VT-005: legacy fixture loads; appearance save does not drop fields', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(legacySettingsBlob()));
    final MemoryIdentityStore identityStore = MemoryIdentityStore(<String, String>{
      IdentityRepository.uuidKey: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      IdentityRepository.callsignKey: 'BRAVO-7',
    });

    final SettingsRepository repo = SettingsRepository(store);
    final IdentityRepository identity = IdentityRepository(identityStore);
    final AppearanceStore appearance = AppearanceStore(store);
    addTearDown(repo.dispose);

    final KeryxSettings loaded = await repo.load();
    expect(loaded.squelchLevel, 8);
    expect(loaded.rogerBeep, RogerBeepVariant.dualTone);
    expect(loaded.totSeconds, 120);
    expect(loaded.busyLockout, isFalse);
    expect(loaded.latchMode, isTrue);
    expect(loaded.characterDspIntensity, CharacterDspIntensity.full);
    expect(loaded.forceLocalOnly, isTrue);
    expect(loaded.isPro, isTrue);
    expect(loaded.relayUrl, 'wss://old.example/relay');
    expect(loaded.tokenServiceUrl, 'https://old.example/token');
    expect(loaded.dimMode, DimMode.auto);

    final DeviceIdentity id = await identity.loadOrCreate();
    expect(id.callsign.value, 'BRAVO-7');

    await appearance.save(
      const AppearancePreference(theme: AppearanceTheme.light));
    await repo.save(loaded.copyWith(dimMode: DimMode.manual));

    final KeryxSettings roundTrip = await repo.load();
    expect(roundTrip.squelchLevel, 8);
    expect(roundTrip.rogerBeep, RogerBeepVariant.dualTone);
    expect(roundTrip.totSeconds, 120);
    expect(roundTrip.busyLockout, isFalse);
    expect(roundTrip.latchMode, isTrue);
    expect(roundTrip.characterDspIntensity, CharacterDspIntensity.full);
    expect(roundTrip.forceLocalOnly, isTrue);
    expect(roundTrip.isPro, isTrue);
    expect(roundTrip.relayUrl, 'wss://old.example/relay');
    expect(roundTrip.tokenServiceUrl, 'https://old.example/token');
    expect(roundTrip.dimMode, DimMode.manual);

    final AppearancePreference theme = await appearance.load();
    expect(theme.theme, AppearanceTheme.light);

    // Settings JSON still has every legacy key — not a reduced object.
    final String? encoded = await store.read(SettingsRepository.storageKey);
    final Map<String, Object?> json = Map<String, Object?>.from(
      jsonDecode(encoded!) as Map<dynamic, dynamic>);
    expect(
      json.keys,
      containsAll(<String>[
        'squelchLevel',
        'rogerBeep',
        'totSeconds',
        'busyLockout',
        'latchMode',
        'characterDspIntensity',
        'forceLocalOnly',
        'isPro',
        'relayUrl',
        'tokenServiceUrl',
        'dimMode',
      ]));
    expect(
      await store.read(AppearancePreference.storageKey),
      isNot(SettingsRepository.storageKey));
  });

  test('invalid relay/token URLs are refused by the UI validator', () {
    expect(isValidRelayUrl(''), isTrue);
    expect(isValidRelayUrl('wss://relay.example'), isTrue);
    expect(isValidRelayUrl('https://relay.example'), isFalse);
    expect(isValidRelayUrl('not a url'), isFalse);
    expect(isValidTokenUrl(''), isTrue);
    expect(isValidTokenUrl('https://token.example/token'), isTrue);
    expect(isValidTokenUrl('wss://token.example'), isFalse);
  });
}
