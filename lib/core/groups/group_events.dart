/// Events [GroupsController] emits so a session/host layer (a later task)
/// can react without polling the store.
library;

/// A group's secret was rotated and this store has already opened and
/// adopted the new one (Technical §5.3) — any live session for [groupId]
/// must switch rooms.
class GroupKeyChanged {
  const GroupKeyChanged({required this.groupId, required this.keyVersion, required this.newRoomId});
  final String groupId;
  final int keyVersion;
  final String newRoomId;
}

/// This identity is no longer a member of [groupId] — either it left, was
/// removed, or a `refreshFromServer` simply no longer lists it (Technical
/// §5.3: "a removed member's copy is not written, so they cannot derive
/// the new room" — detected here as the group vanishing from the server's
/// membership list, since there is no explicit "you were removed" push).
class GroupMembershipEnded {
  const GroupMembershipEnded({required this.groupId});
  final String groupId;
}
