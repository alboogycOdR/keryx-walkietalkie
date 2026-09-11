import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/groups/group_models.dart' show GroupMembership;
import '../../core/groups/groups_controller.dart';
import '../../core/theme/ux_tokens.dart';
import 'group_invite_link.dart';
import 'groups_copy.dart';

/// Join-with-a-code flow (Design §2.3 "Join with a code" floating action):
/// scan a QR or paste a link, decode it (V2-FR-021), and join through
/// [GroupsController]. Refuses an expired invite locally before ever
/// hitting the network (mirrors `event_link.dart`'s own disclosed
/// decision on `isExpired`).
class JoinWithCodeScreen extends StatefulWidget {
  const JoinWithCodeScreen({super.key, required this.groupsController, required this.onJoined});

  final GroupsController groupsController;
  final void Function(GroupMembership membership) onJoined;

  @override
  State<JoinWithCodeScreen> createState() => _JoinWithCodeScreenState();
}

class _JoinWithCodeScreenState extends State<JoinWithCodeScreen> {
  final _pasteController = TextEditingController();
  bool _joining = false;
  String? _error;
  bool _scanning = false;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final decoded = decodeGroupInviteLink(raw);
    switch (decoded) {
      case GroupInviteDecodeFailure():
        setState(() => _error = GroupsCopy.invalidInviteLink);
        return;
      case GroupInviteDecoded(:final link):
        if (link.isExpired()) {
          setState(() => _error = GroupsCopy.expiredInviteLink);
          return;
        }
        setState(() {
          _joining = true;
          _error = null;
        });
        try {
          final membership = await widget.groupsController.joinGroup(
            groupId: link.groupId,
            // The wire contract doesn't carry a group name in the invite
            // payload; the joiner's local row shows the server-supplied
            // name on the very next `refreshFromServer()` sweep. An empty
            // placeholder here is a safe, non-crashing interim value.
            groupName: '',
            token: link.token,
            secret: link.secret,
          );
          if (!mounted) return;
          widget.onJoined(membership);
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _joining = false;
            _error = GroupsCopy.joinFailed;
          });
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(title: const Text(GroupsCopy.joinWithCodeAction)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(GroupsCopy.pasteOrScanPrompt, style: KeryxUxTypography.body.copyWith(color: tokens.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              key: const Key('keryx-join-code-paste'),
              controller: _pasteController,
              decoration: const InputDecoration(labelText: 'Paste an invite link'),
              onSubmitted: _submit,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: tokens.stateEmergency)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('keryx-join-code-submit'),
              onPressed: _joining ? null : () => _submit(_pasteController.text.trim()),
              child: _joining
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(GroupsCopy.joinWithCodeAction),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('keryx-join-code-scan'),
              onPressed: () => setState(() => _scanning = !_scanning),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(_scanning ? 'Stop scanning' : 'Scan a code'),
            ),
            if (_scanning)
              SizedBox(
                height: 240,
                child: MobileScanner(
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isEmpty) return;
                    final raw = barcodes.first.rawValue;
                    if (raw == null) return;
                    setState(() => _scanning = false);
                    _submit(raw);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
