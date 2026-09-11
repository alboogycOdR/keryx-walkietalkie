import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferencesContactsRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repository = SharedPreferencesContactsRepository(await SharedPreferences.getInstance());
  });

  test('round-trips contacts, pending and blocked lists', () async {
    await repository.saveContacts([const Contact(pk: 'a', callsign: 'A')]);
    await repository.savePending([
      const PendingContactRequest(
        pk: 'b',
        callsign: 'B',
        direction: ContactRequestDirection.incoming,
        createdAt: 1,
        expiresAt: 2,
      ),
    ]);
    await repository.saveBlocked([const BlockedContact(pk: 'c', blockedAt: 3)]);

    expect((await repository.loadContacts()).single.pk, 'a');
    expect((await repository.loadPending()).single.pk, 'b');
    expect((await repository.loadBlocked()).single.pk, 'c');
  });

  test('an empty/missing store loads as an empty list, never throws', () async {
    expect(await repository.loadContacts(), isEmpty);
    expect(await repository.loadPending(), isEmpty);
    expect(await repository.loadBlocked(), isEmpty);
  });

  test('saving more than contactsCap contacts keeps only the most recent contactsCap', () async {
    final many = List.generate(contactsCap + 10, (i) => Contact(pk: 'p$i', callsign: 'C$i'));

    await repository.saveContacts(many);
    final loaded = await repository.loadContacts();

    expect(loaded, hasLength(contactsCap));
    expect(loaded.first.pk, 'p10'); // the oldest 10 were dropped
    expect(loaded.last.pk, 'p${contactsCap + 9}');
  });
}
