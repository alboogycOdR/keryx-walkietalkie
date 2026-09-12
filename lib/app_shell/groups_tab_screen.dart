import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/presentation/talk_target.dart'
    show TalkTarget, TalkTargetKind;
import 'package:keryx/features/groups/group_detail_controller.dart';
import 'package:keryx/features/groups/group_detail_screen.dart';
import 'package:keryx/features/groups/group_invite_screen.dart';
import 'package:keryx/features/groups/group_view_models.dart' show GroupListRow;
import 'package:keryx/features/groups/groups_list_screen.dart';
import 'package:keryx/features/groups/join_with_code_screen.dart';
import 'package:keryx/features/groups/new_group_screen.dart';
import 'package:keryx/services/directory/directory.dart' show DirectoryClient;

import 'directory_providers.dart';
import 'shell_keys.dart';

/// Groups tab body (Design §2.3) — mounts TASK-091's [GroupsListScreen] and
/// owns the list->detail->invite/new/join navigation that feature's screens
/// don't wire themselves (each is a standalone widget with injected
/// callbacks, per that task's own `Owned_Paths` note). Row tap switches the
/// shell to Talk with that group as the current target (Design §1).
class GroupsTabScreen extends ConsumerStatefulWidget {
  const GroupsTabScreen({super.key, required this.onSelectTarget});

  final ValueChanged<TalkTarget> onSelectTarget;

  @override
  ConsumerState<GroupsTabScreen> createState() => _GroupsTabScreenState();
}

class _GroupsTabScreenState extends ConsumerState<GroupsTabScreen> {
  List<GroupMembership> _memberships = const [];

  void _onSelectRow(GroupsController controller, GroupListRow row) {
    final membership = controller.groupsSnapshot
        .where((m) => m.id == row.id)
        .cast<GroupMembership?>()
        .firstWhere((m) => true, orElse: () => null);
    if (membership == null) return;
    widget.onSelectTarget(
      TalkTarget(
        kind: TalkTargetKind.group,
        id: membership.id,
        name: membership.name,
        roomId: membership.roomId,
        memberPeerIds: const <String>[],
      ),
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    GroupsController groupsController,
    DirectoryClient directory,
    String myPk,
    String myKeyPairPeerId,
    GroupListRow row,
  ) async {
    final membership = groupsController.groupsSnapshot
        .where((m) => m.id == row.id)
        .cast<GroupMembership?>()
        .firstWhere((m) => true, orElse: () => null);
    if (membership == null) return;
    final identity = await ref.read(identityProvider.future);
    final keyPair = identity.keyPair;
    if (keyPair == null || !context.mounted) return;
    final detailController = GroupDetailController(
      groupId: membership.id,
      groupsController: groupsController,
      directoryClient: directory,
      keyPair: keyPair,
      myPk: myPk,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(
          key: ShellKeys.groupDetail,
          controller: detailController,
          myPk: myPk,
          groupSecret: membership.secret,
        ),
      ),
    );
  }

  Future<void> _openNewGroup(
    BuildContext context,
    GroupsController groupsController,
    DirectoryClient directory,
    String myPk,
  ) async {
    final GroupMembership? created = await Navigator.of(context)
        .push<GroupMembership>(
      MaterialPageRoute<GroupMembership>(
        builder: (_) => NewGroupScreen(
          key: ShellKeys.newGroup,
          groupsController: groupsController,
          onCreated: (membership) => Navigator.of(context).pop(membership),
        ),
      ),
    );
    if (created == null || !context.mounted) return;
    final identity = await ref.read(identityProvider.future);
    final keyPair = identity.keyPair;
    if (keyPair == null || !context.mounted) return;
    final detailController = GroupDetailController(
      groupId: created.id,
      groupsController: groupsController,
      directoryClient: directory,
      keyPair: keyPair,
      myPk: myPk,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => GroupInviteScreen(
          key: ShellKeys.groupInvite,
          controller: detailController,
          groupId: created.id,
          secret: created.secret,
        ),
      ),
    );
  }

  Future<void> _openJoinWithCode(
    BuildContext context,
    GroupsController groupsController,
  ) {
    return Navigator.of(context)
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => JoinWithCodeScreen(
              key: ShellKeys.joinWithCode,
              groupsController: groupsController,
              onJoined: (_) => Navigator.of(context).pop(),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final controllerAsync = ref.watch(groupsControllerProvider);
    final directoryAsync = ref.watch(directoryClientProvider);
    final identityAsync = ref.watch(identityProvider);
    return controllerAsync.when(
      data: (GroupsController? controller) {
        final DirectoryClient? directory = directoryAsync.valueOrNull;
        final myPk = identityAsync.valueOrNull?.peerId;
        if (controller == null || directory == null || myPk == null) {
          return const _GroupsUnavailable();
        }
        return StreamBuilder<List<GroupMembership>>(
          stream: controller.groups,
          initialData: controller.groupsSnapshot,
          builder: (context, snapshot) {
            _memberships = snapshot.data ?? const [];
            final rows = _memberships
                .map(
                  (m) => GroupListRow(
                    id: m.id,
                    name: m.name,
                    onlineCount: 0,
                    totalCount: 1,
                    isAdmin: m.isAdmin,
                  ),
                )
                .toList(growable: false);
            return GroupsListScreen(
              key: ShellKeys.groupsTab,
              rows: rows,
              onSelectTarget: (row) => _onSelectRow(controller, row),
              onOpenDetail: (row) => unawaited(
                _openDetail(context, controller, directory, myPk, myPk, row),
              ),
              onNewGroup: () =>
                  unawaited(_openNewGroup(context, controller, directory, myPk)),
              onJoinWithCode: () =>
                  unawaited(_openJoinWithCode(context, controller)),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object _, StackTrace _) => const _GroupsUnavailable(),
    );
  }
}

class _GroupsUnavailable extends StatelessWidget {
  const _GroupsUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Groups need a relay address. Set one in Settings to create or '
          'join a group.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
