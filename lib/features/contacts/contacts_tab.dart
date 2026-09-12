import 'dart:async';

import 'package:flutter/material.dart';

import 'add_contact_sheet.dart';
import 'contact_actions_sheet.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_list_controller.dart';
import 'contacts_screen.dart';
import 'incoming_request_sheet.dart';
import 'scan_id_screen.dart';

/// Wired Contacts tab: listens to [ContactsListController], presents
/// [ContactsScreen], and owns the add/incoming/actions sheets. TASK-093
/// mounts this; it has no shell or session imports of its own.
class ContactsTab extends StatefulWidget {
  const ContactsTab({
    super.key,
    required this.controller,
    this.onSelectTarget,
    this.onShowMyCode,
    this.scannerBuilder = defaultIdScanner,
    this.autoPresentIncoming = true,
  });

  final ContactsListController controller;
  final void Function(ContactRowVm contact)? onSelectTarget;
  final VoidCallback? onShowMyCode;
  final IdScannerBuilder scannerBuilder;

  /// When true, the first unseen incoming request opens the Design §2.5
  /// modal. Widget tests that drive the list itself set this false.
  final bool autoPresentIncoming;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  StreamSubscription<ContactsViewState>? _sub;
  ContactsViewState _state = ContactsViewState.empty;
  String? _confirmingBlockPk;
  final Set<String> _presentedIncoming = {};

  @override
  void initState() {
    super.initState();
    _state = widget.controller.snapshot;
    _sub = widget.controller.states.listen((next) {
      if (!mounted) return;
      setState(() => _state = next);
      _maybePresentIncoming(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybePresentIncoming(_state);
    });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _maybePresentIncoming(ContactsViewState state) {
    if (!widget.autoPresentIncoming) return;
    if (!mounted) return;
    for (final request in state.requests) {
      if (_presentedIncoming.add(request.pk)) {
        showIncomingRequestSheet(
          context: context,
          request: request,
          onAccept: () => unawaited(widget.controller.accept(request.pk)),
          onDecline: () => unawaited(widget.controller.decline(request.pk)),
          onBlock: () => unawaited(widget.controller.block(request.pk)),
        );
        return;
      }
    }
  }

  Future<String?> _onPaste(String raw) async {
    try {
      final result = await widget.controller.sendRequestFromId(raw);
      if (result is ContactIdInvalid) return result.reason;
      return null;
    } catch (_) {
      return ContactsCopy.requestFailed;
    }
  }

  Future<void> _openScan() async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ScanIdScreen(
          scannerBuilder: widget.scannerBuilder,
          onRaw: (raw) => unawaited(widget.controller.sendRequestFromId(raw)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ContactsScreen(
      state: _state,
      confirmingBlockPk: _confirmingBlockPk,
      onArmBlockRequest: (pk) => setState(() => _confirmingBlockPk = pk),
      onSelectTarget: widget.onSelectTarget,
      onAcceptRequest: (request) {
        setState(() => _confirmingBlockPk = null);
        unawaited(widget.controller.accept(request.pk));
      },
      onDeclineRequest: (request) {
        setState(() => _confirmingBlockPk = null);
        unawaited(widget.controller.decline(request.pk));
      },
      onBlockRequest: (request) {
        setState(() => _confirmingBlockPk = null);
        unawaited(widget.controller.block(request.pk));
      },
      onOpenIncomingRequest: (request) {
        showIncomingRequestSheet(
          context: context,
          request: request,
          onAccept: () => unawaited(widget.controller.accept(request.pk)),
          onDecline: () => unawaited(widget.controller.decline(request.pk)),
          onBlock: () => unawaited(widget.controller.block(request.pk)),
        );
      },
      onLongPressContact: (contact) {
        showContactActionsSheet(
          context: context,
          contact: contact,
          alertDisabled: _state.isAlertDisabled(contact.pk),
          onAlert: () => unawaited(widget.controller.sendAlert(contact.pk)),
          onRemove: () => unawaited(widget.controller.removeContact(contact.pk)),
          onBlock: () => unawaited(widget.controller.block(contact.pk)),
        );
      },
      onAddContact: () {
        showAddContactSheet(
          context: context,
          onScan: () => unawaited(_openScan()),
          onShowMyCode: widget.onShowMyCode,
          onPaste: _onPaste,
        );
      },
    );
  }
}
