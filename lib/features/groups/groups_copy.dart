/// User-facing copy for the Groups tab and group detail screen
/// (Design §2.3, §4, §5 — plain language, never "channel/tune/station/
/// LOCAL/LINKED/AUTO").
library;

abstract final class GroupsCopy {
  static const tabTitle = 'Groups';
  static const emptyStateTitle = 'No groups yet';
  static const emptyStateBody = 'Create a group or join one with a code.';
  static const newGroupAction = 'New group';
  static const joinWithCodeAction = 'Join with a code';
  static const leaveAction = 'Leave';
  static const renameAction = 'Rename';
  static const removeMemberAction = 'Remove member';
  static const rotateKeyAction = 'Rotate key';
  static const makeAdminAction = 'Make admin';
  static const inviteAction = 'Invite';
  static const adminLabel = 'Admin';

  /// Design §4 "Key rotated" toast — the row's `{name}` is substituted by
  /// the caller.
  static String keyRotatedToast(String name) => "$name's key changed; you're still in";

  /// Design §4 "Removed from group" toast.
  static String removedFromGroupToast(String name) => 'You were removed from $name';

  /// Design §2.3 row subtitle.
  static String memberCountLabel({required int online, required int total}) =>
      '$online online · $total member${total == 1 ? '' : 's'}';

  /// PRD V2-FR-022/025 26th-join cap message.
  static const groupFullMessage = 'This group is full (25 members).';

  static const cannotRemoveLastAdmin =
      'Promote another member to admin before leaving.';

  static const invalidInviteLink = "That link isn't a valid invite.";
  static const expiredInviteLink = 'That invite has expired.';
  static const joinFailed = "Couldn't join that group.";

  static const newGroupNamePrompt = 'Group name';
  static const createAction = 'Create';
  static const pasteOrScanPrompt = 'Scan a code or paste a link';
}
