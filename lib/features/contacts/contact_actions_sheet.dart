import 'package:flutter/material.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_keys.dart';

/// Long-press sheet: Alert, Remove, Block (Block is second-tap confirm).
/// Alert is disabled for 10 minutes after use (V2-FR-050).
class ContactActionsSheet extends StatefulWidget {
  const ContactActionsSheet({
    super.key,
    required this.contact,
    this.alertDisabled = false,
    this.onAlert,
    this.onRemove,
    this.onBlock,
  });

  final ContactRowVm contact;
  final bool alertDisabled;
  final VoidCallback? onAlert;
  final VoidCallback? onRemove;
  final VoidCallback? onBlock;

  @override
  State<ContactActionsSheet> createState() => _ContactActionsSheetState();
}

class _ContactActionsSheetState extends State<ContactActionsSheet> {
  bool _blockArmed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return SafeArea(
      child: Padding(
        key: ContactsKeys.actionsSheet,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                widget.contact.displayId,
                style: KeryxUxTypography.body.copyWith(
                  fontFamily: 'Share Tech Mono',
                  color: tokens.textPrimary,
                ),
              ),
            ),
            ListTile(
              key: ContactsKeys.actionsAlert,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text(ContactsCopy.alertAction),
              subtitle: widget.alertDisabled ? const Text(ContactsCopy.alertCooldown) : null,
              enabled: !widget.alertDisabled,
              onTap: widget.alertDisabled
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      widget.onAlert?.call();
                    },
            ),
            ListTile(
              key: ContactsKeys.actionsRemove,
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text(ContactsCopy.removeAction),
              onTap: () {
                Navigator.of(context).pop();
                widget.onRemove?.call();
              },
            ),
            ListTile(
              key: ContactsKeys.actionsBlock,
              leading: Icon(Icons.block, color: tokens.stateTx),
              title: Text(
                _blockArmed ? ContactsCopy.blockConfirmAction : ContactsCopy.blockAction,
                style: TextStyle(color: tokens.stateTx),
              ),
              onTap: () {
                if (!_blockArmed) {
                  setState(() => _blockArmed = true);
                  return;
                }
                Navigator.of(context).pop();
                widget.onBlock?.call();
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showContactActionsSheet({
  required BuildContext context,
  required ContactRowVm contact,
  bool alertDisabled = false,
  VoidCallback? onAlert,
  VoidCallback? onRemove,
  VoidCallback? onBlock,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => ContactActionsSheet(
      contact: contact,
      alertDisabled: alertDisabled,
      onAlert: onAlert,
      onRemove: onRemove,
      onBlock: onBlock,
    ),
  );
}
