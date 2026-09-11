/// Contact/request models (Technical §6.1; PRD V2-FR-010..014).
library;

/// A confirmed, symmetric contact. [status] is the last known presence
/// value (`offline`/`available`/`busy`/`dnd`) merged in from
/// [PresenceUpdate]s by `ContactsController` — this model itself carries
/// no network/socket state.
class Contact {
  const Contact({
    required this.pk,
    required this.callsign,
    this.status = 'offline',
    this.lastSeenAt,
  });

  final String pk;
  final String callsign;
  final String status;
  final int? lastSeenAt;

  Contact copyWith({String? callsign, String? status, int? lastSeenAt}) => Contact(
    pk: pk,
    callsign: callsign ?? this.callsign,
    status: status ?? this.status,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );

  Map<String, Object?> toJson() => {
    'pk': pk,
    'callsign': callsign,
    'status': status,
    'last_seen_at': lastSeenAt,
  };

  factory Contact.fromJson(Map<String, Object?> json) => Contact(
    pk: json['pk'] as String,
    callsign: json['callsign'] as String,
    status: json['status'] as String? ?? 'offline',
    lastSeenAt: json['last_seen_at'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is Contact &&
      other.pk == pk &&
      other.callsign == callsign &&
      other.status == status &&
      other.lastSeenAt == lastSeenAt;

  @override
  int get hashCode => Object.hash(pk, callsign, status, lastSeenAt);

  @override
  String toString() => 'Contact($pk $callsign $status)';
}

/// Which side of a pending contact request this is (V2-FR-011).
enum ContactRequestDirection { incoming, outgoing }

/// One row of `Me.pending_in`/`pending_out` (Technical §4.2's `Me` schema).
class PendingContactRequest {
  const PendingContactRequest({
    required this.pk,
    required this.callsign,
    required this.direction,
    required this.createdAt,
    required this.expiresAt,
  });

  final String pk;
  final String callsign;
  final ContactRequestDirection direction;
  final int createdAt;
  final int expiresAt;

  bool isExpired(int nowUnixSeconds) => nowUnixSeconds >= expiresAt;

  Map<String, Object?> toJson() => {
    'pk': pk,
    'callsign': callsign,
    'direction': direction.name,
    'created_at': createdAt,
    'expires_at': expiresAt,
  };

  factory PendingContactRequest.fromJson(Map<String, Object?> json) => PendingContactRequest(
    pk: json['pk'] as String,
    callsign: json['callsign'] as String,
    direction: (json['direction'] as String?) == 'outgoing'
        ? ContactRequestDirection.outgoing
        : ContactRequestDirection.incoming,
    createdAt: json['created_at'] as int,
    expiresAt: json['expires_at'] as int,
  );

  @override
  bool operator ==(Object other) =>
      other is PendingContactRequest &&
      other.pk == pk &&
      other.callsign == callsign &&
      other.direction == direction &&
      other.createdAt == createdAt &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(pk, callsign, direction, createdAt, expiresAt);

  @override
  String toString() => 'PendingContactRequest($pk $callsign ${direction.name})';
}

/// A public-key this identity has blocked, so a fresh incoming request from
/// it is refused locally without a round trip (mirrors the server's own
/// `blocks` table, Technical §4.1, but this is the client's read-your-own-
/// writes cache — the server remains authoritative).
class BlockedContact {
  const BlockedContact({required this.pk, required this.blockedAt});
  final String pk;
  final int blockedAt;

  Map<String, Object?> toJson() => {'pk': pk, 'blocked_at': blockedAt};

  factory BlockedContact.fromJson(Map<String, Object?> json) =>
      BlockedContact(pk: json['pk'] as String, blockedAt: json['blocked_at'] as int);
}
