/// Drives the Groups list screen: combines [GroupsController]'s local
/// membership stream with a per-group member/presence fetch so the list
/// can show "n online · m members" per Design §2.3, without fabricating a
/// count for a group whose detail hasn't been fetched yet.
library;

import 'dart:async';

import 'package:keryx/core/groups/group_models.dart' show GroupMembership;
import 'package:keryx/core/groups/groups_controller.dart';
import 'package:keryx/services/directory/directory_client.dart';
import 'package:keryx/services/directory/directory_models.dart' show DirectoryGroupMember;

import 'group_view_models.dart';

class GroupsListController {
  GroupsListController({required GroupsController groupsController, required DirectoryClient directoryClient})
    : _groups = groupsController,
      _directory = directoryClient {
    _rowsController.onListen = () {
      _groupsSub = _groups.groups.listen(_onMemberships);
    };
    _rowsController.onCancel = () {
      unawaited(_groupsSub?.cancel());
      _groupsSub = null;
    };
  }

  final GroupsController _groups;
  final DirectoryClient _directory;
  StreamSubscription<List<GroupMembership>>? _groupsSub;
  final Map<String, List<DirectoryGroupMember>> _memberCache = {};
  final _rowsController = StreamController<List<GroupListRow>>.broadcast();

  Stream<List<GroupListRow>> get rows => _rowsController.stream;

  Future<void> _onMemberships(List<GroupMembership> memberships) async {
    _emit(memberships);
    // Best-effort refresh of every group's member/presence count. A
    // per-group failure (offline, momentarily unreachable) must not blank
    // out the whole list — it just keeps that row's last-known (or
    // zeroed) count, matching the "never fabricate" rule in
    // `buildGroupListRow`'s dartdoc.
    for (final membership in memberships) {
      try {
        final detail = await _directory.getGroup(membership.id);
        _memberCache[membership.id] = detail.members;
      } catch (_) {
        // Leave whatever was cached (possibly nothing) alone.
      }
    }
    _emit(memberships);
  }

  void _emit(List<GroupMembership> memberships) {
    if (_rowsController.isClosed) return;
    final rows = memberships
        .map((m) => buildGroupListRow(m, members: _memberCache[m.id]))
        .toList();
    _rowsController.add(rows);
  }

  /// Forces a re-fetch of every group's member/presence counts (e.g. pull
  /// to refresh).
  Future<void> refresh() async {
    await _groups.refreshFromServer();
  }

  Future<void> dispose() async {
    await _groupsSub?.cancel();
    await _rowsController.close();
  }
}
