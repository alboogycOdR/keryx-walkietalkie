import 'package:flutter/material.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_keys.dart';

/// Design §2.5 incoming-request modal: "Add BEN·4R2M?" with Accept
/// (accent), Decline, and Block (destructive, second-tap confirm).
class IncomingRequestSheet extends StatefulWidget {
  const IncomingRequestSheet({
    super.key,
    required this.request,
    this.onAccept,
    this.onDecline,
    this.onBlock,
  });

  final RequestRowVm request;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onBlock;

  @override
  State<IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<IncomingRequestSheet> {
  bool _blockArmed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return SafeArea(
      child: Padding(
        key: ContactsKeys.incomingSheet,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ContactsCopy.addRequestPrompt(widget.request.displayId),
              style: KeryxUxTypography.sectionTitle.copyWith(color: tokens.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.request.displayId,
              style: KeryxUxTypography.body.copyWith(
                color: tokens.textSecondary,
                fontFamily: 'Share Tech Mono',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: ContactsKeys.incomingAccept,
              onPressed: widget.onAccept,
              style: FilledButton.styleFrom(
                minimumSize: KeryxUxSpacing.minTargetSize,
                backgroundColor: tokens.actionPrimary,
                foregroundColor: tokens.surfaceBase,
              ),
              child: const Text(ContactsCopy.acceptAction),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: ContactsKeys.incomingDecline,
              onPressed: widget.onDecline,
              style: OutlinedButton.styleFrom(minimumSize: KeryxUxSpacing.minTargetSize),
              child: const Text(ContactsCopy.declineAction),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: ContactsKeys.incomingBlock,
              onPressed: () {
                if (!_blockArmed) {
                  setState(() => _blockArmed = true);
                  return;
                }
                widget.onBlock?.call();
              },
              style: TextButton.styleFrom(
                minimumSize: KeryxUxSpacing.minTargetSize,
                foregroundColor: tokens.stateTx,
              ),
              child: Text(_blockArmed ? ContactsCopy.blockConfirmAction : ContactsCopy.blockAction),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showIncomingRequestSheet({
  required BuildContext context,
  required RequestRowVm request,
  VoidCallback? onAccept,
  VoidCallback? onDecline,
  VoidCallback? onBlock,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => IncomingRequestSheet(
      request: request,
      onAccept: () {
        Navigator.of(sheetContext).pop();
        onAccept?.call();
      },
      onDecline: () {
        Navigator.of(sheetContext).pop();
        onDecline?.call();
      },
      onBlock: () {
        Navigator.of(sheetContext).pop();
        onBlock?.call();
      },
    ),
  );
}
