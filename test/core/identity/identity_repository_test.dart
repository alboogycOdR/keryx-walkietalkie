import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

import 'memory_identity_store.dart';

void main() {
  test('first run persists an Ed25519 seed and a NATO callsign', () async {
    final store = MemoryIdentityStore();
    final repo = IdentityRepository(store, random: Random(3));
    final id = await repo.loadOrCreate();

    expect(id.keyPair.seed.length, identityKeyLength);
    expect(id.keyPair.publicKey.length, identityKeyLength);
    expect(isPeerId(id.peerId), isTrue);
    expect(id.peerId, derivePeerId(id.keyPair.publicKey));
    expect(id.shortCode, deriveShortCode(id.keyPair.publicKey));
    expect(Callsign.pattern.hasMatch(id.callsign.value), isTrue);
    final storedSeed = base64Decode(
      store.snapshot[IdentityRepository.privateKeySeedKey]!,
    );
    expect(storedSeed, id.keyPair.seed);
    expect(store.snapshot[IdentityRepository.callsignKey], id.callsign.value);
  });

  test('second load returns the same key pair and peerId', () async {
    final store = MemoryIdentityStore();
    final first = await IdentityRepository(
      store,
      random: Random(3),
    ).loadOrCreate();
    final second = await IdentityRepository(
      store,
      random: Random(99),
    ).loadOrCreate();

    expect(second.keyPair.seed, first.keyPair.seed);
    expect(second.keyPair.publicKey, first.keyPair.publicKey);
    expect(second.peerId, first.peerId);
    expect(second.callsign, first.callsign);
  });

  test('editing the callsign does not rotate the key pair or peerId', () async {
    final store = MemoryIdentityStore();
    final repo = IdentityRepository(store, random: Random(5));
    final first = await repo.loadOrCreate();
    final edited = await repo.setCallsign('SIERRA-19');

    expect(edited.callsign.value, 'SIERRA-19');
    expect(edited.peerId, first.peerId);
    expect(edited.keyPair.seed, first.keyPair.seed);
  });

  test('setCallsign rejects an illegal name and leaves storage alone', () async {
    final store = MemoryIdentityStore();
    final repo = IdentityRepository(store, random: Random(5));
    final first = await repo.loadOrCreate();
    expect(() => repo.setCallsign('x'), throwsFormatException);
    final again = await repo.loadOrCreate();
    expect(again.callsign, first.callsign);
    expect(again.peerId, first.peerId);
  });

  test('pre-seeded key is reused and not rewritten', () async {
    final seed = List<int>.generate(32, (i) => i);
    final store = MemoryIdentityStore({
      IdentityRepository.privateKeySeedKey: base64Encode(seed),
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    final id = await IdentityRepository(store, random: Random(1)).loadOrCreate();
    expect(id.keyPair.seed, seed);
    expect(id.callsign.value, 'BRAVO-7');
  });

  test('corrupt seed is regenerated; good callsign is kept', () async {
    final store = MemoryIdentityStore({
      IdentityRepository.privateKeySeedKey: 'not-valid-base64!!!',
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    final id = await IdentityRepository(store, random: Random(8)).loadOrCreate();
    expect(id.keyPair.seed.length, identityKeyLength);
    expect(id.callsign.value, 'BRAVO-7');
  });

  test(
    'migration: a v1 install (UUID + callsign, no key) mints a key and '
    'keeps the callsign (Technical §8)',
    () async {
      final store = MemoryIdentityStore({
        IdentityRepository.legacyUuidKey:
            '00112233-4455-4677-8899-aabbccddeeff',
        IdentityRepository.callsignKey: 'BRAVO-7',
      });
      final id = await IdentityRepository(
        store,
        random: Random(2),
      ).loadOrCreate();

      expect(id.callsign.value, 'BRAVO-7');
      expect(id.keyPair.seed.length, identityKeyLength);
      expect(isPeerId(id.peerId), isTrue);
      expect(
        store.snapshot.containsKey(IdentityRepository.privateKeySeedKey),
        isTrue,
      );
    },
  );

  test('restoreKeyPair overwrites the stored key so the next load matches', () async {
    final store = MemoryIdentityStore();
    final repo = IdentityRepository(store, random: Random(9));
    final original = await repo.loadOrCreate();

    final phrase = RecoveryPhrase.generate(random: Random(11));
    final restored = await phrase.deriveKeyPair();
    await repo.restoreKeyPair(restored);

    final afterRestore = await repo.loadOrCreate();
    expect(afterRestore.keyPair.publicKey, restored.publicKey);
    expect(afterRestore.peerId, isNot(original.peerId));
  });
}
