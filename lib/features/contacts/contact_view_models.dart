/// Pure view-model helpers for the Contacts tab — no I/O, no widgets
/// (Design §2.2, §3, §4; PRD V2-FR-010..014, V2-FR-030/031).
library;

import 'package:keryx/core/contacts/contact_models.dart';
import 'package:keryx/core/identity/peer_id.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';

import 'contacts_copy.dart';

/// Wire presence plus the two derived cues (Design §3).
enum PresenceVisual { available, busy, dnd, offline }

PresenceVisual presenceVisualFor(String? status) => switch (status) {
  'available' => PresenceVisual.available,
  'busy' => PresenceVisual.busy,
  'dnd' => PresenceVisual.dnd,
  _ => PresenceVisual.offline,
};

/// Design §3 word for the four statuses — colour is never the only cue.
String presenceWord(PresenceVisual visual) => switch (visual) {
  PresenceVisual.available => ContactsCopy.availableLabel,
  PresenceVisual.busy => ContactsCopy.busyLabel,
  PresenceVisual.dnd => ContactsCopy.dndLabel,
  PresenceVisual.offline => ContactsCopy.offlineLabel,
};

/// Design §3 "Offline · 2 h ago". [nowUnixSeconds] and [lastSeenAt] are
/// unix seconds. Missing or sub-minute last-seen collapses to just
/// "Offline" rather than fabricating a duration.
String offlinePresenceLabel({required int nowUnixSeconds, int? lastSeenAt}) {
  if (lastSeenAt == null) return ContactsCopy.offlineLabel;
  final delta = nowUnixSeconds - lastSeenAt;
  if (delta < 60) return ContactsCopy.offlineLabel;
  if (delta < 3600) {
    final minutes = delta ~/ 60;
    return '${ContactsCopy.offlineLabel} · $minutes min ago';
  }
  if (delta < 86400) {
    final hours = delta ~/ 3600;
    return '${ContactsCopy.offlineLabel} · $hours h ago';
  }
  final days = delta ~/ 86400;
  return '${ContactsCopy.offlineLabel} · $days d ago';
}

/// Short code shown in mono next to the callsign (Design §2.2).
///
/// Real directory `pk` values are unpadded base64url of the 32-byte
/// Ed25519 public key (Technical §3.1) — those derive the 4-character
/// code. Opaque test/fixture pks fall back to a 4-character prefix so a
/// row never renders blank.
String shortCodeForPk(String pk) {
  try {
    final key = decodeUnpaddedBase64Url(pk);
    if (key.length == 32) return deriveShortCode(key);
  } on FormatException {
    // Fall through to the opaque-pk prefix.
  }
  final trimmed = pk.trim();
  if (trimmed.length >= 4) return trimmed.substring(0, 4).toUpperCase();
  return trimmed.toUpperCase().padRight(4, 'X');
}

String displayIdFor({required String callsign, required String shortCode}) =>
    '$callsign·$shortCode';

/// Local decode of a scanned or pasted ID (V2-FR-010; V2-VT-003).
/// A tampered or malformed payload is refused here — no network.
sealed class ContactIdParse {
  const ContactIdParse();
}

final class ContactIdParsed extends ContactIdParse {
  const ContactIdParsed(this.link);
  final KeryxIdLink link;
}

final class ContactIdInvalid extends ContactIdParse {
  const ContactIdInvalid(this.reason);
  final String reason;
}

ContactIdParse parseContactId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const ContactIdInvalid(ContactsCopy.invalidId);
  }
  try {
    return ContactIdParsed(KeryxIdLink.parse(trimmed));
  } on FormatException {
    return const ContactIdInvalid(ContactsCopy.tamperedId);
  }
}

/// One incoming request row (Design §2.2 Requests section).
class RequestRowVm {
  const RequestRowVm({
    required this.pk,
    required this.callsign,
    required this.shortCode,
  });

  final String pk;
  final String callsign;
  final String shortCode;

  String get displayId => displayIdFor(callsign: callsign, shortCode: shortCode);
}

/// One Contacts-section row, including outgoing "waiting" rows (Design §4).
class ContactRowVm {
  const ContactRowVm({
    required this.pk,
    required this.callsign,
    required this.shortCode,
    required this.visual,
    this.lastSeenAt,
    this.isTalking = false,
    this.isNearby = false,
    this.isOutgoingPending = false,
  });

  final String pk;
  final String callsign;
  final String shortCode;
  final PresenceVisual visual;
  final int? lastSeenAt;
  final bool isTalking;
  final bool isNearby;
  final bool isOutgoingPending;

  String get displayId => displayIdFor(callsign: callsign, shortCode: shortCode);

  /// Presence word, with the Design §3 offline relative-time form.
  String presenceLabel({required int nowUnixSeconds}) {
    if (isOutgoingPending) return ContactsCopy.waitingToAccept(callsign);
    if (visual == PresenceVisual.offline) {
      return offlinePresenceLabel(nowUnixSeconds: nowUnixSeconds, lastSeenAt: lastSeenAt);
    }
    return presenceWord(visual);
  }

  /// TalkBack label: state word is always present so colour is never the
  /// only cue (Design §3, §6).
  String semanticLabel({required int nowUnixSeconds}) {
    final parts = <String>[
      callsign,
      shortCode,
      presenceLabel(nowUnixSeconds: nowUnixSeconds),
    ];
    if (isNearby) parts.add(ContactsCopy.nearbyLabel);
    if (isTalking) parts.add(ContactsCopy.talkingLabel);
    return parts.join(', ');
  }
}

/// One frame of the Contacts tab.
class ContactsViewState {
  const ContactsViewState({
    required this.requests,
    required this.contacts,
    required this.alertDisabledPks,
    required this.nowUnixSeconds,
  });

  final List<RequestRowVm> requests;
  final List<ContactRowVm> contacts;
  final Set<String> alertDisabledPks;
  final int nowUnixSeconds;

  bool get isEmpty => requests.isEmpty && contacts.isEmpty;

  bool isAlertDisabled(String pk) => alertDisabledPks.contains(pk);

  static const empty = ContactsViewState(
    requests: [],
    contacts: [],
    alertDisabledPks: {},
    nowUnixSeconds: 0,
  );
}

/// Maps TASK-086 store snapshots into presentation rows. [talkingPks] /
/// [nearbyPks] are injected (no session dependency — TASK-093 can pass
/// live sets later).
ContactsViewState buildContactsViewState({
  required List<PendingContactRequest> pending,
  required List<Contact> contacts,
  required Set<String> talkingPks,
  required Set<String> nearbyPks,
  required Set<String> alertDisabledPks,
  required int nowUnixSeconds,
}) {
  final incoming = pending.where((p) => p.direction == ContactRequestDirection.incoming).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final outgoing = pending.where((p) => p.direction == ContactRequestDirection.outgoing).toList();

  final requestRows = [
    for (final p in incoming)
      RequestRowVm(pk: p.pk, callsign: p.callsign, shortCode: shortCodeForPk(p.pk)),
  ];

  final contactRows = <ContactRowVm>[
    for (final c in contacts)
      ContactRowVm(
        pk: c.pk,
        callsign: c.callsign,
        shortCode: shortCodeForPk(c.pk),
        visual: presenceVisualFor(c.status),
        lastSeenAt: c.lastSeenAt,
        isTalking: talkingPks.contains(c.pk),
        isNearby: nearbyPks.contains(c.pk),
      ),
    for (final p in outgoing)
      ContactRowVm(
        pk: p.pk,
        callsign: p.callsign,
        shortCode: shortCodeForPk(p.pk),
        visual: PresenceVisual.offline,
        isOutgoingPending: true,
      ),
  ]..sort((a, b) {
      if (a.isOutgoingPending != b.isOutgoingPending) {
        return a.isOutgoingPending ? 1 : -1;
      }
      return a.callsign.toLowerCase().compareTo(b.callsign.toLowerCase());
    });

  return ContactsViewState(
    requests: requestRows,
    contacts: contactRows,
    alertDisabledPks: Set<String>.unmodifiable(alertDisabledPks),
    nowUnixSeconds: nowUnixSeconds,
  );
}

/// V2-FR-050: one Alert per target per 10 minutes.
const Duration alertCooldown = Duration(minutes: 10);

bool alertIsOnCooldown({
  required int lastAlertAtUnixSeconds,
  required int nowUnixSeconds,
  Duration cooldown = alertCooldown,
}) =>
    nowUnixSeconds - lastAlertAtUnixSeconds < cooldown.inSeconds;
