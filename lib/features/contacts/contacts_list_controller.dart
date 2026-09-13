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

  /// Disk first (so the UI is instant — the [contacts]/[pending] streams
  /// emit the disk-backed snapshot immediately), then a server refresh
  /// (§1). Unlike the other refresh triggers (tab open, foreground, the
  /// timer), `load()`'s own refresh is *awaited*, not fire-and-forget:
  /// this is the "open Contacts and see a pending request with no other
  /// action" path (journey gate 6), which has to be a deterministic
  /// outcome of `await load()`, not a race against whenever the network
  /// call happens to land.
  Future<void> load() async {
    await _contacts.loadFromDisk();
    _emit();
    await refresh();
  }

  /// Pulls the directory's current view (TASK-105 §1) and reconciles the
  /// local store to match. A failing refresh (offline, not yet registered)
  /// is swallowed here — [ContactsController.refreshFromServer] never
  /// mutates local state before it succeeds, so the disk-backed snapshot is
  /// simply left as it was; this is the one place callers that don't care
  /// about the outcome (tab open, foreground, the timer) can call without
  /// a try/catch of their own.
  Future<void> refresh() async {
    try {
      await _contacts.refreshFromServer();
    } catch (_) {
      // Offline or `unknown_identity` before registration — not fatal.
    }
  }

  Future<void> accept(String pk) async {
    await _contacts.accept(pk);
    unawaited(refresh());
  }

  Future<void> decline(String pk) async {
    await _contacts.decline(pk);
    unawaited(refresh());
  }

  /// Block a pending requester **or** an existing contact. The directory's
  /// `:block` endpoint records the block and drops a contact pair if one
  /// exists (Technical §4.2); locally we remove first so the row leaves
  /// the list without waiting for a `getMe` refresh.
  Future<void> block(String pk) async {
    if (_contacts.contactsSnapshot.any((c) => c.pk == pk)) {
      await _contacts.removeContact(pk);
    }
    await _contacts.block(pk);
    unawaited(refresh());
  }

  Future<void> removeContact(String pk) async {
    await _contacts.removeContact(pk);
    unawaited(refresh());
  }

  /// Parse locally, then send. A tampered QR never hits the network
  /// (V2-VT-003).
  Future<ContactIdParse> sendRequestFromId(String raw) async {
    final parsed = parseContactId(raw);
    if (parsed is ContactIdInvalid) return parsed;
    final link = (parsed as ContactIdParsed).link;
    await _contacts.sendRequest(link.encodedKey, callsign: link.callsign);
    unawaited(refresh());
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
