/// Pure view-model helpers for the Groups tab and detail screen — no I/O,
/// no widget imports, easy to test exhaustively (Design §2.3, §3, §4;
/// PRD V2-FR-020..025).
library;

import 'package:keryx/core/groups/group_models.dart' show GroupMembership;
import 'package:keryx/services/directory/directory_models.dart' show DirectoryGroupMember;

/// PRD V2-FR-022 group size cap. The server is authoritative (refuses the
/// 26th join); this constant is used only for a fast client-side "this
/// group is full" affordance before ever hitting the network.
const int groupMemberCap = 25;

/// One row model for the Groups list (Design §2.3): "glyph, name, n online
/// · m members".
class GroupListRow {
  const GroupListRow({
    required this.id,
    required this.name,
    required this.onlineCount,
    required this.totalCount,
    required this.isAdmin,
  });

  final String id;
  final String name;
  final int onlineCount;
  final int totalCount;
  final bool isAdmin;

  /// First letter of [name], uppercased, for the glyph placeholder — falls
  /// back to '?' for an empty name rather than throwing.
  String get glyph => name.isEmpty ? '?' : name[0].toUpperCase();
}

/// One row in the group detail member list.
class MemberRow {
  const MemberRow({
    required this.pk,
    required this.callsign,
    required this.isAdmin,
    required this.status,
    required this.isMe,
  });

  final String pk;
  final String callsign;
  final bool isAdmin;

  /// Wire status string (`available|busy|dnd|offline`) or `null` when
  /// unknown (e.g. the member row hasn't been presence-merged yet).
  final String? status;
  final bool isMe;

  bool get isOnline => status != null && status != 'offline';
}

/// Presence-dot state per Design §3's table. `null`/unrecognised statuses
/// fall back to [offline] rather than throwing — an unknown wire value
/// must never crash a row render.
enum PresenceDotState { available, busy, dnd, offline }

PresenceDotState presenceDotStateFor(String? status) => switch (status) {
  'available' => PresenceDotState.available,
  'busy' => PresenceDotState.busy,
  'dnd' => PresenceDotState.dnd,
  _ => PresenceDotState.offline,
};

/// Design §3's word for each dot state — colour is never the only cue.
String presenceDotLabel(PresenceDotState state) => switch (state) {
  PresenceDotState.available => 'Available',
  PresenceDotState.busy => 'Busy',
  PresenceDotState.dnd => 'Do Not Disturb',
  PresenceDotState.offline => 'Offline',
};

/// Members whose [DirectoryGroupMember.status] counts as "online" for the
/// Design §2.3 "n online" count — any non-offline, non-null status.
int onlineCountOf(List<DirectoryGroupMember> members) =>
    members.where((m) => m.status != null && m.status != 'offline').length;

/// Builds a [GroupListRow] from a locally-adopted [membership] and the
/// (optionally still-unknown) server member list for it. When [members]
/// is `null` (detail not yet fetched), online/total default to 0 rather
/// than fabricating a count (Design §2.1/§2.4's "never a fabricated
/// presence count" rule, carried here for groups too).
GroupListRow buildGroupListRow(
  GroupMembership membership, {
  List<DirectoryGroupMember>? members,
}) => GroupListRow(
  id: membership.id,
  name: membership.name,
  onlineCount: members == null ? 0 : onlineCountOf(members),
  totalCount: members?.length ?? 0,
  isAdmin: membership.isAdmin,
);

/// Converts server [members] into [MemberRow]s, admins first then
/// alphabetical by callsign — a stable, presentation-only ordering.
List<MemberRow> buildMemberRows(
  List<DirectoryGroupMember> members, {
  required String myPk,
}) {
  final rows = members
      .map(
        (m) => MemberRow(
          pk: m.pk,
          callsign: m.callsign,
          isAdmin: m.role == 'admin',
          status: m.status,
          isMe: m.pk == myPk,
        ),
      )
      .toList();
  rows.sort((a, b) {
    if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;
    return a.callsign.toLowerCase().compareTo(b.callsign.toLowerCase());
  });
  return rows;
}

/// True when [myPk] is the only admin among [members] — the "last-admin
/// leave" gate (V2-FR-023/024).
bool isLastAdmin(List<DirectoryGroupMember> members, String myPk) {
  final admins = members.where((m) => m.role == 'admin');
  return admins.length == 1 && admins.first.pk == myPk;
}

/// Picks who the last admin's [leave] should promote before leaving: the
/// member list's first non-admin, non-self entry — server member lists
/// are returned in join order (`group_members` primary-key order per
/// Technical §4.1's schema), so the first entry standing is the oldest
/// remaining member. Returns `null` when nobody is left to promote (a
/// solo group — the caller then just leaves/deletes membership normally).
DirectoryGroupMember? oldestMemberToPromote(
  List<DirectoryGroupMember> members, {
  required String myPk,
}) {
  for (final member in members) {
    if (member.pk != myPk && member.role != 'admin') return member;
  }
  for (final member in members) {
    if (member.pk != myPk) return member;
  }
  return null;
}

/// PRD V2-FR-022: the 26th join is refused. `>=` because [members].length
/// already counts everyone currently in, and the cap forbids the group
/// from ever holding more than [groupMemberCap] + creator === 25 total.
bool isGroupFull(int currentMemberCount) => currentMemberCount >= groupMemberCap;
