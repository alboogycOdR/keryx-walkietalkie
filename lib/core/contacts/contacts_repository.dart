/// Local persistence for contacts/pending requests/blocks
/// (Technical §6.1: "`shared_preferences` JSON with a 500-entry cap" —
/// `sqflite` is not in `pubspec.yaml` and it is frozen after TASK-083).
///
/// A typed repository interface so the backing store can be swapped later
/// without touching [ContactsController].
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'contact_models.dart';

/// Hard cap on persisted contacts (Technical §6.1). Enforced on write: the
/// oldest contact (by insertion order, since [Contact] carries no
/// added-at) is dropped to make room for a new one past the cap, so a
/// pathological server response can never grow local storage unbounded.
const contactsCap = 500;

abstract class ContactsRepository {
  Future<List<Contact>> loadContacts();
  Future<void> saveContacts(List<Contact> contacts);

  Future<List<PendingContactRequest>> loadPending();
  Future<void> savePending(List<PendingContactRequest> pending);

  Future<List<BlockedContact>> loadBlocked();
  Future<void> saveBlocked(List<BlockedContact> blocked);
}

class SharedPreferencesContactsRepository implements ContactsRepository {
  SharedPreferencesContactsRepository(this._prefs);

  static const _contactsKey = 'keryx.v2.contacts';
  static const _pendingKey = 'keryx.v2.contacts.pending';
  static const _blockedKey = 'keryx.v2.contacts.blocked';

  final SharedPreferences _prefs;

  @override
  Future<List<Contact>> loadContacts() => Future.value(_loadList(_contactsKey, Contact.fromJson));

  @override
  Future<void> saveContacts(List<Contact> contacts) {
    final capped = contacts.length > contactsCap
        ? contacts.sublist(contacts.length - contactsCap)
        : contacts;
    return _saveList(_contactsKey, capped, (c) => c.toJson());
  }

  @override
  Future<List<PendingContactRequest>> loadPending() =>
      Future.value(_loadList(_pendingKey, PendingContactRequest.fromJson));

  @override
  Future<void> savePending(List<PendingContactRequest> pending) =>
      _saveList(_pendingKey, pending, (p) => p.toJson());

  @override
  Future<List<BlockedContact>> loadBlocked() =>
      Future.value(_loadList(_blockedKey, BlockedContact.fromJson));

  @override
  Future<void> saveBlocked(List<BlockedContact> blocked) =>
      _saveList(_blockedKey, blocked, (b) => b.toJson());

  List<T> _loadList<T>(String key, T Function(Map<String, Object?>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, Object?>>().map(fromJson).toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> _saveList<T>(
    String key,
    List<T> items,
    Map<String, Object?> Function(T) toJson,
  ) async {
    await _prefs.setString(key, jsonEncode(items.map(toJson).toList()));
  }
}
