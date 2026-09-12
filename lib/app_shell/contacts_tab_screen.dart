import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/contacts/contacts_controller.dart'
    show ContactsController;
import 'package:keryx/core/presentation/talk_target.dart'
    show TalkTarget, TalkTargetKind;
import 'package:keryx/core/rooms/derivation.dart' show deriveDirectRoom;
import 'package:keryx/features/contacts/contacts.dart';
import 'package:keryx/services/directory/directory.dart' show DirectoryClient;

import 'directory_providers.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';

/// Contacts tab body (Design §2.2, ADR-002-style `embedded` composition) —
/// mounts TASK-090's [ContactsTab] over the real [ContactsController] this
/// shell composes in [contactsControllerProvider]. Row tap builds a v2
/// [TalkTarget] and switches the shell to Talk (Design §1 "Current
/// target"); floating "Show my code" opens the ⋮ menu's My code route.
class ContactsTabScreen extends ConsumerWidget {
  const ContactsTabScreen({super.key, required this.onSelectTarget});

  final ValueChanged<TalkTarget> onSelectTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllerAsync = ref.watch(contactsControllerProvider);
    final directoryAsync = ref.watch(directoryClientProvider);
    return controllerAsync.when(
      data: (ContactsController? controller) {
        final DirectoryClient? directory = directoryAsync.valueOrNull;
        if (controller == null || directory == null) {
          return const _ContactsUnavailable();
        }
        return ContactsTab(
          key: ShellKeys.contactsTab,
          controller: ContactsListController(
            contactsController: controller,
            directoryClient: directory,
          ),
          onSelectTarget: (ContactRowVm contact) =>
              unawaited(_selectContact(ref, contact, onSelectTarget)),
          onShowMyCode: () => ShellRoutes.openMyCode(context),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object _, StackTrace _) => const _ContactsUnavailable(),
    );
  }

  static Future<void> _selectContact(
    WidgetRef ref,
    ContactRowVm contact,
    ValueChanged<TalkTarget> onSelectTarget,
  ) async {
    final identity = await ref.read(identityProvider.future);
    final keyPair = identity.keyPair;
    if (keyPair == null) return;
    final theirPublicKey = decodeUnpaddedBase64Url(contact.pk);
    if (theirPublicKey == null) return;
    final roomId = await deriveDirectRoom(
      myKeyPair: keyPair,
      theirEdwardsPublicKey: theirPublicKey,
    );
    onSelectTarget(
      TalkTarget(
        kind: TalkTargetKind.contact,
        id: contact.pk,
        name: contact.callsign,
        roomId: roomId,
        memberPeerIds: <String>[contact.pk],
      ),
    );
  }
}

/// Decodes the v2 directory's unpadded base64url public-key wire form
/// (Technical §3.1/§3.3 — the encode-side counterpart,
/// `unpaddedBase64Url`, lives in `lib/services/directory/directory_signing.dart`,
/// frozen territory; this is the decode side this shell needs and that file
/// does not expose). Returns `null` rather than throwing on malformed input
/// — a corrupt stored contact must not crash target selection.
List<int>? decodeUnpaddedBase64Url(String value) {
  try {
    final padded = base64Url.normalize(value);
    return base64Url.decode(padded);
  } on FormatException {
    return null;
  }
}

class _ContactsUnavailable extends StatelessWidget {
  const _ContactsUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Contacts need a relay address. Set one in Settings to add '
          'contacts and see presence.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
