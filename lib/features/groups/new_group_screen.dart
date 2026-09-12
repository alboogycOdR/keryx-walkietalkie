import 'package:flutter/material.dart';

import '../../core/groups/group_models.dart' show GroupMembership;
import '../../core/groups/groups_controller.dart';
import '../../core/theme/ux_tokens.dart';
import 'groups_copy.dart';

/// Name entry → create flow (Design §2.3 "New group" floating action).
/// On success, hands the freshly created [GroupMembership] to [onCreated]
/// (typically to push straight into the invite screen) rather than owning
/// navigation itself.
class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key, required this.groupsController, required this.onCreated});

  final GroupsController groupsController;
  final void Function(GroupMembership membership) onCreated;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _controller = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a group name.');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final membership = await widget.groupsController.createGroup(name);
      if (!mounted) return;
      widget.onCreated(membership);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = "Couldn't create that group.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(title: const Text(GroupsCopy.newGroupAction)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('keryx-new-group-name'),
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: GroupsCopy.newGroupNamePrompt),
              onSubmitted: (_) => _create(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: tokens.stateEmergency)),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('keryx-new-group-create'),
              onPressed: _creating ? null : _create,
              child: _creating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(GroupsCopy.createAction),
            ),
          ],
        ),
      ),
    );
  }
}
