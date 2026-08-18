import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';

import 'memory_identity_store.dart';

void main() {
  test('first run persists a UUID v4 and a NATO callsign', () async {
    final store = MemoryIdentityStore();
    final repo = IdentityRepository(store, random: Random(3));
    final id = await repo.loadOrCreate();

    expect(isCanonicalUuid(id.installUuid), isTrue);
    expect(id.installUuid[14], '4');
    expect(isPeerId(id.peerId), isTrue);
    expect(id.peerId, derivePeerId(id.installUuid));
    expect(Callsign.pattern.hasMatch(id.callsign.value), isTrue);
    expect(store.snapshot[IdentityRepository.uuidKey], id.installUuid);
    expect(store.snapshot[IdentityRepository.callsignKey], id.callsign.value);
  });

  test('second load returns the same UUID and peerId', () async {
    final store = MemoryIdentityStore();
    final first = await IdentityRepository(store, random: Random(3)).loadOrCreate();
    final second = await IdentityRepository(
      store,
      random: Random(99),
    ).loadOrCreate();

    expect(second.installUuid, first.installUuid);
    expect(second.peerId, first.peerId);
    expect(second.callsign, first.callsign);
  });

  test('editing the callsign does not rotate peerId or UUID', () async {
    final store = MemoryIdentityStore();
    final repo = IdentityRepository(store, random: Random(5));
    final first = await repo.loadOrCreate();
    final edited = await repo.setCallsign('SIERRA-19');

    expect(edited.callsign.value, 'SIERRA-19');
    expect(edited.peerId, first.peerId);
    expect(edited.installUuid, first.installUuid);
    expect(store.snapshot[IdentityRepository.uuidKey], first.installUuid);
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

  test('pre-seeded UUID is reused and not rewritten', () async {
    const uuid = '00112233-4455-4677-8899-aabbccddeeff';
    final store = MemoryIdentityStore({
      IdentityRepository.uuidKey: uuid,
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    final id = await IdentityRepository(store, random: Random(1)).loadOrCreate();
    expect(id.installUuid, uuid);
    expect(id.peerId, 'wvuni74syc');
    expect(id.callsign.value, 'BRAVO-7');
  });

  test('corrupt UUID is regenerated; good callsign is kept', () async {
    final store = MemoryIdentityStore({
      IdentityRepository.uuidKey: 'nope',
      IdentityRepository.callsignKey: 'BRAVO-7',
    });
    final id = await IdentityRepository(store, random: Random(8)).loadOrCreate();
    expect(isCanonicalUuid(id.installUuid), isTrue);
    expect(id.installUuid, isNot('nope'));
    expect(id.callsign.value, 'BRAVO-7');
  });
}
