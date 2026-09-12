/// Group detail screen: member list, admin actions, invite (Design §2.3,
/// §3, §4; PRD V2-FR-020..025). Renders [GroupDetailController]'s state and
/// toast streams; admin-only actions are fully hidden (not just disabled)
/// for non-admins.
library;

import 'package:flutter/material.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'group_detail_controller.dart';
import 'group_invite_screen.dart';
import 'group_view_models.dart';
import 'groups_copy.dart';

/// Keys for widget tests.
abstract final class GroupDetailKeys {
  static const Key title = Key('group-detail.title');
  static const Key memberList = Key('group-detail.member-list');
  static const Key leaveAction = Key('group-detail.leave');
  static const Key renameAction = Key('group-detail.rename');
  static const Key rotateKeyAction = Key('group-detail.rotate-key');
  static const Key inviteAction = Key('group-detail.invite');
  static const Key toast = Key('group-detail.toast');
  static Key memberRow(String pk) => Key('group-detail.member.$pk');
  static Key removeMember(String pk) => Key('group-detail.remove.$pk');
  static Key makeAdmin(String pk) => Key('group-detail.make-admin.$pk');
}

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.controller,
    required this.myPk,
    required this.groupSecret,
    this.onLeft,
  });

  final GroupDetailController controller;
  final String myPk;

  /// This identity's already-opened secret for the group being shown
  /// (`GroupMembership.secret`) — carried into [GroupInviteScreen] the
  /// same way the sender already holds it; this screen never re-derives
  /// or re-fetches it.
  final List<int> groupSecret;

  /// Called after a successful [GroupDetailController.leave] — the caller
  /// decides how to pop/navigate away.
  final VoidCallback? onLeft;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late GroupDetailState _state;
  String? _toast;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.state;
    widget.controller.states.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
    widget.controller.toasts.listen((t) {
      if (!mounted) return;
      setState(() => _toast = t.message);
    });
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: Text(state.name, key: GroupDetailKeys.title)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_toast != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  key: GroupDetailKeys.toast,
                  padding: const EdgeInsets.all(KeryxUxSpacing.controlGap),
                  child: Text(_toast!, style: KeryxUxTypography.secondary.copyWith(color: tokens.textSecondary)),
                ),
              ),
            if (state.loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(child: _memberList(tokens, state)),
            _actionsBar(tokens, state),
          ],
        ),
      ),
    );
  }

  Widget _memberList(KeryxUxTokens tokens, GroupDetailState state) {
    return ListView.builder(
      key: GroupDetailKeys.memberList,
      itemCount: state.members.length,
      itemBuilder: (context, index) {
        final member = state.members[index];
        return ListTile(
          key: GroupDetailKeys.memberRow(member.pk),
          leading: _presenceDot(presenceDotStateFor(member.status)),
          title: Text(member.callsign, style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary)),
          subtitle: member.isAdmin
              ? Text(GroupsCopy.adminLabel, style: KeryxUxTypography.secondary.copyWith(color: tokens.textSecondary))
              : null,
          trailing: state.isAdmin && !member.isMe
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!member.isAdmin)
                      IconButton(
                        key: GroupDetailKeys.makeAdmin(member.pk),
                        icon: const Icon(Icons.shield_outlined),
                        tooltip: GroupsCopy.makeAdminAction,
                        onPressed: () => widget.controller.makeAdmin(member.pk),
                      ),
                    IconButton(
                      key: GroupDetailKeys.removeMember(member.pk),
                      icon: const Icon(Icons.person_remove_outlined),
                      tooltip: GroupsCopy.removeMemberAction,
                      onPressed: () => widget.controller.removeMember(member.pk),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }

  Widget _presenceDot(PresenceDotState state) {
    final color = switch (state) {
      PresenceDotState.available => Colors.green,
      PresenceDotState.busy => Colors.orange,
      PresenceDotState.dnd => Colors.red,
      PresenceDotState.offline => Colors.grey,
    };
    return Semantics(
      label: presenceDotLabel(state),
      child: CircleAvatar(radius: 6, backgroundColor: color),
    );
  }

  Widget _actionsBar(KeryxUxTokens tokens, GroupDetailState state) {
    return Padding(
      padding: const EdgeInsets.all(KeryxUxSpacing.pageMargin),
      child: Wrap(
        spacing: KeryxUxSpacing.controlGap,
        children: [
          OutlinedButton(
            key: GroupDetailKeys.inviteAction,
            onPressed: _openInvite,
            child: const Text(GroupsCopy.inviteAction),
          ),
          if (state.isAdmin) ...[
            OutlinedButton(
              key: GroupDetailKeys.renameAction,
              onPressed: _promptRename,
              child: const Text(GroupsCopy.renameAction),
            ),
            OutlinedButton(
              key: GroupDetailKeys.rotateKeyAction,
              onPressed: widget.controller.rotateKey,
              child: const Text(GroupsCopy.rotateKeyAction),
            ),
          ],
          OutlinedButton(
            key: GroupDetailKeys.leaveAction,
            onPressed: _leave,
            child: const Text(GroupsCopy.leaveAction),
          ),
        ],
      ),
    );
  }

  Future<void> _leave() async {
    final ok = await widget.controller.leave();
    if (ok) widget.onLeft?.call();
  }

  Future<void> _promptRename() async {
    final controller = TextEditingController(text: _state.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(GroupsCopy.renameAction),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text(GroupsCopy.createAction),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.controller.rename(name);
    }
  }

  Future<void> _openInvite() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupInviteScreen(
          controller: widget.controller,
          groupId: _state.groupId,
          secret: widget.groupSecret,
        ),
      ),
    );
  }
}
