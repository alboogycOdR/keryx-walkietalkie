/// Hand-written typed models for the v2 directory REST contract
/// (`token-svc/openapi-v2.yaml`'s `Me` schema and the group/contact shapes
/// nested inside it). Kept independent of `lib/core/contacts/**` and
/// `lib/core/groups/**` — those own the persisted, presence-merged view;
/// these are the raw wire shapes this client parses responses into.
library;

/// `POST /v2/identity` response.
class IdentityRegistration {
  const IdentityRegistration({required this.pk, required this.callsign});

  /// Unpadded base64url public key (Technical §3.1/§3.3).
  final String pk;
  final String callsign;

  factory IdentityRegistration.fromJson(Map<String, Object?> json) => IdentityRegistration(
    pk: json['pk'] as String,
    callsign: json['callsign'] as String,
  );
}

/// One entry in `Me.contacts`.
class DirectoryContact {
  const DirectoryContact({
    required this.pk,
    required this.callsign,
    required this.status,
    this.lastSeenAt,
  });

  final String pk;
  final String callsign;
  final String status;
  final int? lastSeenAt;

  factory DirectoryContact.fromJson(Map<String, Object?> json) => DirectoryContact(
    pk: json['pk'] as String,
    callsign: json['callsign'] as String,
    status: json['status'] as String? ?? 'offline',
    lastSeenAt: json['last_seen_at'] as int?,
  );
}

/// One entry in `Me.pending_in`.
class DirectoryPendingIn {
  const DirectoryPendingIn({
    required this.fromPk,
    required this.callsign,
    required this.createdAt,
    required this.expiresAt,
  });

  final String fromPk;
  final String callsign;
  final int createdAt;
  final int expiresAt;

  factory DirectoryPendingIn.fromJson(Map<String, Object?> json) => DirectoryPendingIn(
    fromPk: json['from_pk'] as String,
    callsign: json['callsign'] as String,
    createdAt: json['created_at'] as int,
    expiresAt: json['expires_at'] as int,
  );
}

/// One entry in `Me.pending_out`. The contract leaves its schema open
/// (`type: object`, no declared properties); shaped to mirror pending_in.
class DirectoryPendingOut {
  const DirectoryPendingOut({
    required this.toPk,
    required this.callsign,
    required this.createdAt,
    required this.expiresAt,
  });

  final String toPk;
  final String callsign;
  final int createdAt;
  final int expiresAt;

  factory DirectoryPendingOut.fromJson(Map<String, Object?> json) => DirectoryPendingOut(
    toPk: json['to_pk'] as String,
    callsign: json['callsign'] as String? ?? '',
    createdAt: json['created_at'] as int? ?? 0,
    expiresAt: json['expires_at'] as int? ?? 0,
  );
}

/// One entry in `Me.groups` — "id, name, role, key_version, secret_enc".
class DirectoryGroupMembership {
  const DirectoryGroupMembership({
    required this.id,
    required this.name,
    required this.role,
    required this.keyVersion,
    required this.secretEnc,
  });

  final String id;
  final String name;

  /// `"admin"` or `"member"`.
  final String role;
  final int keyVersion;

  /// This member's sealed copy of the group secret (base64), openable only
  /// with this identity's private key (`openSealed`, TASK-083).
  final String secretEnc;

  factory DirectoryGroupMembership.fromJson(Map<String, Object?> json) => DirectoryGroupMembership(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    keyVersion: json['key_version'] as int,
    secretEnc: json['secret_enc'] as String,
  );
}

/// `GET /v2/identity/me` response — the full `Me` schema.
class DirectoryMe {
  const DirectoryMe({
    required this.pk,
    required this.callsign,
    required this.status,
    required this.contacts,
    required this.pendingIn,
    required this.pendingOut,
    required this.groups,
  });

  final String pk;
  final String callsign;
  final String status;
  final List<DirectoryContact> contacts;
  final List<DirectoryPendingIn> pendingIn;
  final List<DirectoryPendingOut> pendingOut;
  final List<DirectoryGroupMembership> groups;

  factory DirectoryMe.fromJson(Map<String, Object?> json) => DirectoryMe(
    pk: json['pk'] as String,
    callsign: json['callsign'] as String,
    status: json['status'] as String,
    contacts: ((json['contacts'] as List?) ?? const [])
        .map((e) => DirectoryContact.fromJson(e as Map<String, Object?>))
        .toList(),
    pendingIn: ((json['pending_in'] as List?) ?? const [])
        .map((e) => DirectoryPendingIn.fromJson(e as Map<String, Object?>))
        .toList(),
    pendingOut: ((json['pending_out'] as List?) ?? const [])
        .map((e) => DirectoryPendingOut.fromJson(e as Map<String, Object?>))
        .toList(),
    groups: ((json['groups'] as List?) ?? const [])
        .map((e) => DirectoryGroupMembership.fromJson(e as Map<String, Object?>))
        .toList(),
  );
}

/// `POST /v2/groups`, `POST /v2/groups/join`, `POST /v2/groups/{id}/invites`,
/// `GET /v2/groups/{id}` responses — kept intentionally loose (the contract
/// doesn't pin every field) but typed for what this client actually reads.
class DirectoryGroupCreated {
  const DirectoryGroupCreated({required this.id});
  final String id;
  factory DirectoryGroupCreated.fromJson(Map<String, Object?> json) =>
      DirectoryGroupCreated(id: json['id'] as String);
}

class DirectoryInvite {
  const DirectoryInvite({required this.token, required this.expiresAt, required this.groupId});
  final String token;
  final int? expiresAt;
  final String groupId;
  factory DirectoryInvite.fromJson(Map<String, Object?> json) => DirectoryInvite(
    token: json['token'] as String,
    expiresAt: json['expires_at'] as int?,
    groupId: json['group_id'] as String,
  );
}

class DirectoryGroupMember {
  const DirectoryGroupMember({
    required this.pk,
    required this.callsign,
    required this.role,
    this.status,
  });
  final String pk;
  final String callsign;
  final String role;
  final String? status;
  factory DirectoryGroupMember.fromJson(Map<String, Object?> json) => DirectoryGroupMember(
    pk: json['pk'] as String,
    callsign: json['callsign'] as String? ?? '',
    role: json['role'] as String? ?? 'member',
    status: json['status'] as String?,
  );
}

class DirectoryGroupDetail {
  const DirectoryGroupDetail({
    required this.id,
    required this.name,
    required this.keyVersion,
    required this.members,
  });
  final String id;
  final String name;
  final int keyVersion;
  final List<DirectoryGroupMember> members;
  factory DirectoryGroupDetail.fromJson(Map<String, Object?> json) => DirectoryGroupDetail(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    keyVersion: json['key_version'] as int? ?? 0,
    members: ((json['members'] as List?) ?? const [])
        .map((e) => DirectoryGroupMember.fromJson(e as Map<String, Object?>))
        .toList(),
  );
}
