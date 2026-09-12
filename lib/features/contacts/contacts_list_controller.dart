/// Drives the Contacts tab: presence-merged store → [ContactsViewState],
/// plus Alert cooldown and ID-parse-then-request (Design §2.2; V2-FR-010,
/// V2-FR-050). No session or shell dependencies.
library;

import 'dart:async';

import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/services/directory/directory.dart';

import 'contact_view_models.dart';

enum AlertSendResult { sent, cooldown, failed }

class ContactsListController {
  ContactsListController({
    required ContactsController contactsController,
    required DirectoryClient directoryClient,
    Set<String>? talkingPks,
    Set<String>? nearbyPks,
    int Function()? nowUnixSeconds,
  }) : _contacts = contactsController,
       _directory = directoryClient,
       _talkingPks = {...?talkingPks},
       _nearbyPks = {...?nearbyPks},
       _now = nowUnixSeconds ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) {
    _contactsSub = _contacts.contacts.listen((_) => _emit());
    _pendingSub = _contacts.pending.listen((_) => _emit());
  }

  final ContactsController _contacts;
  final DirectoryClient _directory;
  final int Function() _now;
  final Set<String> _talkingPks;
  final Set<String> _nearbyPks;
  final Map<String, int> _lastAlertAt = {};

  StreamSubscription<List<Contact>>? _contactsSub;
  StreamSubscription<List<PendingContactRequest>>? _pendingSub;

  final _states = StreamController<ContactsViewState>.broadcast(sync: true);

  Stream<ContactsViewState> get states => _states.stream;

  ContactsViewState get snapshot => _build();

  /// Optional derived cues (V2-FR-031). The shell can push live sets;
  /// this task has no session to observe them from.
  void setTalkingPks(Set<String> pks) {
    _talkingPks
      ..clear()
      ..addAll(pks);
    _emit();
  }

  void setNearbyPks(Set<String> pks) {
    _nearbyPks
      ..clear()
      ..addAll(pks);
    _emit();
  }

  Future<void> load() async {
    await _contacts.loadFromDisk();
    _emit();
  }

  Future<void> accept(String pk) => _contacts.accept(pk);

  Future<void> decline(String pk) => _contacts.decline(pk);

  /// Block a pending requester **or** an existing contact. The directory's
  /// `:block` endpoint records the block and drops a contact pair if one
  /// exists (Technical §4.2); locally we remove first so the row leaves
  /// the list without waiting for a `getMe` refresh.
  Future<void> block(String pk) async {
    if (_contacts.contactsSnapshot.any((c) => c.pk == pk)) {
      await _contacts.removeContact(pk);
    }
    await _contacts.block(pk);
  }

  Future<void> removeContact(String pk) => _contacts.removeContact(pk);

  /// Parse locally, then send. A tampered QR never hits the network
  /// (V2-VT-003).
  Future<ContactIdParse> sendRequestFromId(String raw) async {
    final parsed = parseContactId(raw);
    if (parsed is ContactIdInvalid) return parsed;
    final link = (parsed as ContactIdParsed).link;
    await _contacts.sendRequest(link.encodedKey, callsign: link.callsign);
    return parsed;
  }

  bool isAlertDisabled(String pk) {
    final last = _lastAlertAt[pk];
    if (last == null) return false;
    return alertIsOnCooldown(lastAlertAtUnixSeconds: last, nowUnixSeconds: _now());
  }

  /// V2-FR-050: disable the control for 10 minutes after a successful
  /// send, and also after the server refuses with `alert_rate_limited`.
  Future<AlertSendResult> sendAlert(String pk) async {
    if (isAlertDisabled(pk)) return AlertSendResult.cooldown;
    try {
      await _directory.sendAlert(pk);
      _lastAlertAt[pk] = _now();
      _emit();
      return AlertSendResult.sent;
    } on DirectoryException catch (e) {
      if (e.code == DirectoryErrorCode.alertRateLimited) {
        _lastAlertAt[pk] = _now();
        _emit();
        return AlertSendResult.cooldown;
      }
      return AlertSendResult.failed;
    }
  }

  ContactsViewState _build() {
    final disabled = <String>{
      for (final entry in _lastAlertAt.entries)
        if (alertIsOnCooldown(lastAlertAtUnixSeconds: entry.value, nowUnixSeconds: _now())) entry.key,
    };
    return buildContactsViewState(
      pending: _contacts.pendingSnapshot,
      contacts: _contacts.contactsSnapshot,
      talkingPks: _talkingPks,
      nearbyPks: _nearbyPks,
      alertDisabledPks: disabled,
      nowUnixSeconds: _now(),
    );
  }

  void _emit() {
    if (_states.isClosed) return;
    _states.add(_build());
  }

  Future<void> dispose() async {
    await _contactsSub?.cancel();
    await _pendingSub?.cancel();
    await _states.close();
  }
}
