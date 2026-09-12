import 'package:flutter/material.dart';

import '../../core/theme/ux_tokens.dart';
import 'contact_view_models.dart';
import 'contacts_copy.dart';
import 'contacts_keys.dart';
import 'presence_badge.dart';

/// Contacts tab body (Design §2.2): no app bar of its own (`embedded`
/// like TASK-075/076). Sections: Requests then Contacts. Purely
/// presentational — owns no store.
class ContactsScreen extends StatelessWidget {
  const ContactsScreen({
    super.key,
    required this.state,
    this.onSelectTarget,
    this.onLongPressContact,
    this.onAcceptRequest,
    this.onDeclineRequest,
    this.onBlockRequest,
    this.onOpenIncomingRequest,
    this.onAddContact,
    this.confirmingBlockPk,
    this.onArmBlockRequest,
  });

  final ContactsViewState state;

  final void Function(ContactRowVm contact)? onSelectTarget;
  final void Function(ContactRowVm contact)? onLongPressContact;
  final void Function(RequestRowVm request)? onAcceptRequest;
  final void Function(RequestRowVm request)? onDeclineRequest;
  final void Function(RequestRowVm request)? onBlockRequest;
  final void Function(RequestRowVm request)? onOpenIncomingRequest;
  final VoidCallback? onAddContact;

  /// pk of the request row whose Block control is armed for the second
  /// tap (Design §2.5). Owned by the parent so a rebuild from the store
  /// doesn't lose it.
  final String? confirmingBlockPk;
  final void Function(String pk)? onArmBlockRequest;

  @override
  Widget build(BuildContext context) {
    final tokens = KeryxUxTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surfaceBase,
      body: state.isEmpty
          ? _EmptyState(tokens: tokens)
          : _ContactsBody(
              state: state,
              tokens: tokens,
              onSelectTarget: onSelectTarget,
              onLongPressContact: onLongPressContact,
              onAcceptRequest: onAcceptRequest,
              onDeclineRequest: onDeclineRequest,
              onBlockRequest: onBlockRequest,
              onOpenIncomingRequest: onOpenIncomingRequest,
              confirmingBlockPk: confirmingBlockPk,
              onArmBlockRequest: onArmBlockRequest,
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: ContactsKeys.addFab,
        onPressed: onAddContact,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text(ContactsCopy.addContactAction),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens});
  final KeryxUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: ContactsKeys.empty,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 48, color: tokens.textSecondary),
            const SizedBox(height: 12),
            Text(
              ContactsCopy.emptyStateTitle,
              style: KeryxUxTypography.sectionTitle.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              ContactsCopy.emptyStateBody,
              textAlign: TextAlign.center,
              style: KeryxUxTypography.body.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactsBody extends StatelessWidget {
  const _ContactsBody({
    required this.state,
    required this.tokens,
    this.onSelectTarget,
    this.onLongPressContact,
    this.onAcceptRequest,
    this.onDeclineRequest,
    this.onBlockRequest,
    this.onOpenIncomingRequest,
    this.confirmingBlockPk,
    this.onArmBlockRequest,
  });

  final ContactsViewState state;
  final KeryxUxTokens tokens;
  final void Function(ContactRowVm contact)? onSelectTarget;
  final void Function(ContactRowVm contact)? onLongPressContact;
  final void Function(RequestRowVm request)? onAcceptRequest;
  final void Function(RequestRowVm request)? onDeclineRequest;
  final void Function(RequestRowVm request)? onBlockRequest;
  final void Function(RequestRowVm request)? onOpenIncomingRequest;
  final String? confirmingBlockPk;
  final void Function(String pk)? onArmBlockRequest;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: ContactsKeys.list,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        if (state.requests.isNotEmpty) ...[
          _SectionHeader(label: ContactsCopy.requestsSection, tokens: tokens, sectionKey: ContactsKeys.requestsSection),
          const SizedBox(height: 8),
          for (final request in state.requests) ...[
            _RequestRow(
              request: request,
              tokens: tokens,
              blockArmed: confirmingBlockPk == request.pk,
              onOpen: onOpenIncomingRequest == null ? null : () => onOpenIncomingRequest!(request),
              onAccept: onAcceptRequest == null ? null : () => onAcceptRequest!(request),
              onDecline: onDeclineRequest == null ? null : () => onDeclineRequest!(request),
              onBlock: () {
                if (confirmingBlockPk != request.pk) {
                  onArmBlockRequest?.call(request.pk);
                  return;
                }
                onBlockRequest?.call(request);
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
        ],
        if (state.contacts.isNotEmpty) ...[
          _SectionHeader(label: ContactsCopy.contactsSection, tokens: tokens, sectionKey: ContactsKeys.contactsSection),
          const SizedBox(height: 8),
          for (final contact in state.contacts) ...[
            _ContactRow(
              contact: contact,
              tokens: tokens,
              nowUnixSeconds: state.nowUnixSeconds,
              onTap: contact.isOutgoingPending || onSelectTarget == null
                  ? null
                  : () => onSelectTarget!(contact),
              onLongPress: contact.isOutgoingPending || onLongPressContact == null
                  ? null
                  : () => onLongPressContact!(contact),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.tokens, required this.sectionKey});
  final String label;
  final KeryxUxTokens tokens;
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      key: sectionKey,
      style: KeryxUxTypography.sectionTitle.copyWith(color: tokens.textPrimary),
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.tokens,
    required this.blockArmed,
    this.onOpen,
    this.onAccept,
    this.onDecline,
    this.onBlock,
  });

  final RequestRowVm request;
  final KeryxUxTokens tokens;
  final bool blockArmed;
  final VoidCallback? onOpen;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ContactsKeys.requestRow(request.pk),
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.callsign,
                style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
              ),
              Text(
                request.shortCode,
                style: KeryxUxTypography.compact.copyWith(
                  color: tokens.textSecondary,
                  fontFamily: 'Share Tech Mono',
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    key: ContactsKeys.requestAccept(request.pk),
                    onPressed: onAccept,
                    style: TextButton.styleFrom(
                      minimumSize: KeryxUxSpacing.minTargetSize,
                      foregroundColor: tokens.actionPrimary,
                    ),
                    child: const Text(ContactsCopy.acceptAction),
                  ),
                  TextButton(
                    key: ContactsKeys.requestDecline(request.pk),
                    onPressed: onDecline,
                    style: TextButton.styleFrom(minimumSize: KeryxUxSpacing.minTargetSize),
                    child: const Text(ContactsCopy.declineAction),
                  ),
                  TextButton(
                    key: ContactsKeys.requestBlock(request.pk),
                    onPressed: onBlock,
                    style: TextButton.styleFrom(
                      minimumSize: KeryxUxSpacing.minTargetSize,
                      foregroundColor: tokens.stateTx,
                    ),
                    child: Text(blockArmed ? ContactsCopy.blockConfirmAction : ContactsCopy.blockAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.tokens,
    required this.nowUnixSeconds,
    this.onTap,
    this.onLongPress,
  });

  final ContactRowVm contact;
  final KeryxUxTokens tokens;
  final int nowUnixSeconds;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final label = contact.presenceLabel(nowUnixSeconds: nowUnixSeconds);
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ContactsKeys.contactRow(contact.pk),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Semantics(
            label: contact.semanticLabel(nowUnixSeconds: nowUnixSeconds),
            button: onTap != null,
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        backgroundColor: tokens.surfaceRaised,
                        child: Text(
                          contact.callsign.isEmpty ? '?' : contact.callsign[0].toUpperCase(),
                          style: TextStyle(color: tokens.textPrimary),
                        ),
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: PresenceDot(
                          key: ContactsKeys.presenceDot(contact.pk),
                          visual: contact.visual,
                          isTalking: contact.isTalking,
                          tokens: tokens,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        contact.callsign,
                        style: KeryxUxTypography.body.copyWith(color: tokens.textPrimary),
                      ),
                      Text(
                        contact.shortCode,
                        style: KeryxUxTypography.compact.copyWith(
                          color: tokens.textSecondary,
                          fontFamily: 'Share Tech Mono',
                        ),
                      ),
                      const SizedBox(height: 2),
                      ExcludeSemantics(
                        child: PresenceBadge(
                          visual: contact.visual,
                          label: label,
                          isTalking: contact.isTalking,
                          isNearby: contact.isNearby,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
