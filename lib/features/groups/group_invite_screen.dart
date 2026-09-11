import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/ux_tokens.dart';
import 'group_detail_controller.dart';
import 'group_invite_link.dart';
import 'groups_copy.dart';

/// Invite QR + link screen (Design §2.3/Technical §5.2), reached from
/// [GroupDetailScreen]'s Invite row. Mints an invite, honouring the
/// expiry presets shared with `event_link.dart`.
class GroupInviteScreen extends StatefulWidget {
  const GroupInviteScreen({
    super.key,
    required this.controller,
    required this.groupId,
    required this.secret,
    this.initialPreset = EventLinkExpiryPreset.twentyFourHours,
  });

  final GroupDetailController controller;
  final String groupId;
  final List<int> secret;
  final EventLinkExpiryPreset initialPreset;

  @override
  State<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends State<GroupInviteScreen> {
  late EventLinkExpiryPreset _preset = widget.initialPreset;
  Uri? _link;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _mint();
  }

  Future<void> _mint() async {
    setState(() => _loading = true);
    final invite = await widget.controller.mintInvite(expiresIn: _preset.duration?.inSeconds);
    if (!mounted) return;
    if (invite == null) {
      setState(() {
        _loading = false;
        _link = null;
      });
      return;
    }
    final expiresAt = _preset.duration == null ? null : DateTime.now().add(_preset.duration!);
    final link = GroupInviteLink(
      groupId: widget.groupId,
      token: invite.token,
      secret: widget.secret,
      expiresAt: expiresAt,
    );
    setState(() {
      _loading = false;
      _link = encodeGroupInviteLink(link, preset: _preset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      appBar: AppBar(title: const Text(GroupsCopy.inviteAction)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_link == null)
              Expanded(child: Center(child: Text(GroupsCopy.joinFailed)))
            else ...[
              Expanded(
                child: Center(
                  child: QrImageView(
                    key: const Key('keryx-group-invite-qr'),
                    data: _link.toString(),
                    size: 220,
                  ),
                ),
              ),
              SelectableText(_link.toString(), key: const Key('keryx-group-invite-link-text')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('keryx-group-invite-copy'),
                onPressed: () => Clipboard.setData(ClipboardData(text: _link.toString())),
                icon: const Icon(Icons.copy),
                label: const Text('Copy link'),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButton<EventLinkExpiryPreset>(
              key: const Key('keryx-group-invite-expiry'),
              value: _preset,
              items: EventLinkExpiryPreset.values
                  .map((preset) => DropdownMenuItem(value: preset, child: Text(preset.label)))
                  .toList(),
              onChanged: (preset) {
                if (preset == null) return;
                setState(() => _preset = preset);
                _mint();
              },
            ),
          ],
        ),
      ),
    );
  }
}
