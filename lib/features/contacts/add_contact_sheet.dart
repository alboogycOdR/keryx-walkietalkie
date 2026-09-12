import 'package:flutter/material.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_keys.dart';

/// Design §2.2 add-contact sheet: Scan a code, Show my code, Paste an ID.
class AddContactSheet extends StatefulWidget {
  const AddContactSheet({
    super.key,
    this.onScan,
    this.onShowMyCode,
    this.onPaste,
  });

  final VoidCallback? onScan;
  final VoidCallback? onShowMyCode;

  /// Called with the raw pasted string. Return an error message to keep
  /// the sheet open, or `null` on success (the sheet then pops).
  final Future<String?> Function(String raw)? onPaste;

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final _paste = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _paste.text;
    final local = parseContactId(raw);
    if (local is ContactIdInvalid) {
      setState(() => _error = local.reason);
      return;
    }
    if (widget.onPaste == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onPaste!(raw);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return SafeArea(
      child: Padding(
        key: ContactsKeys.addSheet,
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ContactsCopy.addContactAction,
              style: KeryxUxTypography.sectionTitle.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: 12),
            ListTile(
              key: ContactsKeys.addScan,
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text(ContactsCopy.scanACode),
              onTap: () {
                Navigator.of(context).maybePop();
                widget.onScan?.call();
              },
            ),
            ListTile(
              key: ContactsKeys.addShowMyCode,
              leading: const Icon(Icons.qr_code_2),
              title: const Text(ContactsCopy.showMyCode),
              onTap: () {
                Navigator.of(context).maybePop();
                widget.onShowMyCode?.call();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: ContactsKeys.addPasteField,
              controller: _paste,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: ContactsCopy.pasteAnId,
                hintText: ContactsCopy.pasteHint,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: ContactsKeys.addError,
                  style: TextStyle(color: tokens.stateEmergency),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: ContactsKeys.addPasteSubmit,
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(ContactsCopy.sendRequestAction),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

Future<void> showAddContactSheet({
  required BuildContext context,
  VoidCallback? onScan,
  VoidCallback? onShowMyCode,
  Future<String?> Function(String raw)? onPaste,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AddContactSheet(
      onScan: onScan,
      onShowMyCode: onShowMyCode,
      onPaste: onPaste,
    ),
  );
}
