/// Contacts store + request state machine (Technical §6.1; PRD
/// V2-FR-010..014). Owns the persisted, presence-merged view; the wire
/// layer (`lib/services/directory/**`) is injected, not owned.
///
/// State machine (V2-FR-011): an incoming/outgoing pending request is
/// `pending` until accepted (→ symmetric contact, both sides' pending rows
/// gone), declined (→ pending row gone, no contact), blocked (→ pending row
/// gone, [BlockedContact] recorded so a fresh request from that key can be
/// refused locally), or it expires (7 days server-side; this store prunes
/// any pending row past `expiresAt` on every [refreshFromServer] and
/// exposes [pruneExpired] directly for a deterministic test clock).
library;

import 'dart:async';

import 'package:keryx/services/directory/directory.dart';

import 'contact_models.dart';
import 'contacts_repository.dart';

class ContactsController {
  ContactsController({
    required DirectoryClient directoryClient,
    required ContactsRepository repository,
    PresenceClient? presenceClient,
    int Function()? nowUnixSeconds,
    Duration silenceThreshold = const Duration(minutes: 5),
    Duration? silenceSweepInterval,
  }) : _directory = directoryClient,
       _repository = repository,
       _now = nowUnixSeconds ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000),
       _silenceThresholdSeconds = silenceThreshold.inSeconds {
    if (presenceClient != null) {
      _presenceSub = presenceClient.updates.listen(_onPresenceUpdate);
    }
    if (silenceSweepInterval != null) {
      _silenceSweepTimer = Timer.periodic(silenceSweepInterval, (_) => checkSilence());
    }
  }

  final DirectoryClient _directory;
  final ContactsRepository _repository;
  final int Function() _now;
  final int _silenceThresholdSeconds;
  StreamSubscription<PresenceUpdate>? _presenceSub;
  Timer? _silenceSweepTimer;

  /// Last time (unix seconds) a live [PresenceUpdate] was actually seen for
  /// a contact — separate from the persisted `lastSeenAt` so a restart
  /// doesn't immediately treat every contact as silent (Technical §4.3's
  /// server-side "Offline after 5 minutes without a heartbeat" is mirrored
  /// here client-side via [checkSilence] for contacts whose *last known*
  /// status was non-offline but whose socket has gone quiet).
  final Map<String, int> _lastPresenceSeenAt = {};

  final _contactsController = StreamController<List<Contact>>.broadcast(sync: true);
  final _pendingController = StreamController<List<PendingContactRequest>>.broadcast(sync: true);

  List<Contact> _contacts = const [];
  List<PendingContactRequest> _pending = const [];
  List<BlockedContact> _blocked = const [];
  bool _loaded = false;

  Stream<List<Contact>> get contacts => _contactsController.stream;
  Stream<List<PendingContactRequest>> get pending => _pendingController.stream;

  List<Contact> get contactsSnapshot => List.unmodifiable(_contacts);
  List<PendingContactRequest> get pendingSnapshot => List.unmodifiable(_pending);

  Future<void> loadFromDisk() async {
    _contacts = await _repository.loadContacts();
    _pending = await _repository.loadPending();
    _blocked = await _repository.loadBlocked();
    _loaded = true;
    _emitContacts();
    _emitPending();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await loadFromDisk();
  }

  /// Pulls `GET /v2/identity/me` and reconciles the local store to exactly
  /// match the server: contacts and pending rows not present server-side
  /// are dropped (this is also how a request the *other* side resolved —
  /// e.g. they declined it — disappears locally without a push). Existing
  /// contact rows keep their locally-merged presence status when the
  /// server doesn't carry a fresher one.
  Future<void> refreshFromServer() async {
    await _ensureLoaded();
    final me = await _directory.getMe();
    final serverContacts = {for (final c in me.contacts) c.pk: c};
    _contacts = [
      for (final entry in serverContacts.entries)
        Contact(
          pk: entry.key,
          callsign: entry.value.callsign,
          status: entry.value.status,
          lastSeenAt: entry.value.lastSeenAt,
        ),
    ];
    _pending = [
      for (final p in me.pendingIn)
        PendingContactRequest(
          pk: p.fromPk,
          callsign: p.callsign,
          direction: ContactRequestDirection.incoming,
          createdAt: p.createdAt,
          expiresAt: p.expiresAt,
        ),
      for (final p in me.pendingOut)
        PendingContactRequest(
          pk: p.toPk,
          callsign: p.callsign,
          direction: ContactRequestDirection.outgoing,
          createdAt: p.createdAt,
          expiresAt: p.expiresAt,
        ),
    ];
    pruneExpired();
    await _persistContacts();
    await _persistPending();
  }

  /// Drops any pending row whose `expiresAt` has passed. Called on every
  /// [refreshFromServer]; exposed directly so a test can drive expiry with
  /// a controlled clock instead of a real 7-day wait.
  void pruneExpired() {
    final now = _now();
    final before = _pending.length;
    _pending = _pending.where((p) => !p.isExpired(now)).toList();
    if (_pending.length != before) _emitPending();
  }

  Future<void> sendRequest(String toPk, {required String callsign}) async {
    await _ensureLoaded();
    await _directory.sendContactRequest(toPk); // throws DirectoryException on refusal (incl. too_many_outstanding)
    final now = _now();
    _pending = [
      ..._pending.where((p) => p.pk != toPk),
      PendingContactRequest(
        pk: toPk,
        callsign: callsign,
        direction: ContactRequestDirection.outgoing,
        createdAt: now,
        expiresAt: now + const Duration(days: 7).inSeconds,
      ),
    ];
    await _persistPending();
  }

  Future<void> accept(String fromPk) async {
    await _ensureLoaded();
    final incoming = _pending.firstWhere(
      (p) => p.pk == fromPk && p.direction == ContactRequestDirection.incoming,
      orElse: () => throw StateError('no incoming pending request from $fromPk'),
    );
    await _directory.acceptContactRequest(fromPk);
    _pending = _pending.where((p) => p.pk != fromPk).toList();
    _contacts = [
      ..._contacts.where((c) => c.pk != fromPk),
      Contact(pk: fromPk, callsign: incoming.callsign),
    ];
    await _persistPending();
    await _persistContacts();
  }

  Future<void> decline(String fromPk) async {
    await _ensureLoaded();
    await _directory.declineContactRequest(fromPk);
    _pending = _pending.where((p) => p.pk != fromPk).toList();
    await _persistPending();
  }

  Future<void> block(String fromPk) async {
    await _ensureLoaded();
    await _directory.blockContactRequest(fromPk);
    _pending = _pending.where((p) => p.pk != fromPk).toList();
    _blocked = [..._blocked.where((b) => b.pk != fromPk), BlockedContact(pk: fromPk, blockedAt: _now())];
    await _persistPending();
    await _repository.saveBlocked(_blocked);
  }

  Future<void> removeContact(String pk) async {
    await _ensureLoaded();
    await _directory.removeContact(pk);
    _contacts = _contacts.where((c) => c.pk != pk).toList();
    await _persistContacts();
  }

  bool isBlocked(String pk) => _blocked.any((b) => b.pk == pk);

  void _onPresenceUpdate(PresenceUpdate update) {
    _lastPresenceSeenAt[update.pk] = _now();
    final idx = _contacts.indexWhere((c) => c.pk == update.pk);
    if (idx < 0) return;
    final next = [..._contacts];
    next[idx] = next[idx].copyWith(status: update.status, lastSeenAt: update.since);
    _contacts = next;
    _emitContacts();
    unawaited(_persistContacts());
  }

  /// Marks any contact whose live presence has gone quiet for at least
  /// `silenceThreshold` (constructor param, default 5 minutes) as
  /// `offline` locally — the client-side mirror of the server's own
  /// "Offline after 5 minutes without a heartbeat" (Technical §4.3). A
  /// contact that has never sent a live update since this controller
  /// started is *not* swept (no baseline to measure silence from) — it
  /// keeps whatever status the last [refreshFromServer] gave it until a
  /// live update establishes one.
  ///
  /// Called automatically every `silenceSweepInterval` if one was passed
  /// to the constructor (opt-in; a later session/host wiring task decides
  /// the production cadence), and always callable directly — which is how
  /// a test simulates "5 minutes of silence" without a real timer, via an
  /// injected `nowUnixSeconds` clock.
  void checkSilence() {
    final now = _now();
    var changed = false;
    final next = [..._contacts];
    for (var i = 0; i < next.length; i++) {
      final contact = next[i];
      if (contact.status == 'offline') continue;
      final lastSeen = _lastPresenceSeenAt[contact.pk];
      if (lastSeen == null) continue;
      if (now - lastSeen >= _silenceThresholdSeconds) {
        next[i] = contact.copyWith(status: 'offline');
        changed = true;
      }
    }
    if (changed) {
      _contacts = next;
      _emitContacts();
      unawaited(_persistContacts());
    }
  }

  Future<void> _persistContacts() async {
    await _repository.saveContacts(_contacts);
    _emitContacts();
  }

  Future<void> _persistPending() async {
    await _repository.savePending(_pending);
    _emitPending();
  }

  void _emitContacts() {
    if (!_contactsController.isClosed) _contactsController.add(List.unmodifiable(_contacts));
  }

  void _emitPending() {
    if (!_pendingController.isClosed) _pendingController.add(List.unmodifiable(_pending));
  }

  Future<void> dispose() async {
    _silenceSweepTimer?.cancel();
    await _presenceSub?.cancel();
    await _contactsController.close();
    await _pendingController.close();
  }
}
