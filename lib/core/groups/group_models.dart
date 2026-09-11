/// Group models (Technical §5, §6.1; PRD V2-FR-020..025).
library;

/// One group this identity is a member of, with the secret opened locally
/// (never persisted in plaintext across the wire — only this device's
/// [GroupsRepository] holds the opened bytes, at rest on the same phone
/// that already holds the private key that opened them).
class GroupMembership {
  const GroupMembership({
    required this.id,
    required this.name,
    required this.role,
    required this.keyVersion,
    required this.secret,
    required this.roomId,
  });

  final String id;
  final String name;

  /// `"admin"` or `"member"`.
  final String role;
  final int keyVersion;

  /// The opened (plaintext) group secret — 32 random bytes (Technical
  /// §5.1), used to derive the room id and the LiveKit E2EE key.
  final List<int> secret;

  /// `deriveGroupRoom(secret)` (TASK-087), cached so callers don't need to
  /// re-derive it (and so a rotation's new room id is recorded exactly
  /// once, at the point this store learned the new secret).
  final String roomId;

  bool get isAdmin => role == 'admin';

  GroupMembership copyWith({
    String? name,
    String? role,
    int? keyVersion,
    List<int>? secret,
    String? roomId,
  }) => GroupMembership(
    id: id,
    name: name ?? this.name,
    role: role ?? this.role,
    keyVersion: keyVersion ?? this.keyVersion,
    secret: secret ?? this.secret,
    roomId: roomId ?? this.roomId,
  );
}

/// A group's member roster (Technical §4.2 `GET /v2/groups/{id}`), without
/// this identity's own secret — used for the members list UI, not for
/// deriving anything.
class GroupMemberInfo {
  const GroupMemberInfo({required this.pk, required this.callsign, required this.role, this.status});
  final String pk;
  final String callsign;
  final String role;
  final String? status;

  bool get isAdmin => role == 'admin';
}
