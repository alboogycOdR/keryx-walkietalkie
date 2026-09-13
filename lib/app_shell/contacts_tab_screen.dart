import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueListenable;
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
///
/// TASK-105: owns exactly one [ContactsListController] for as long as this
/// widget stays mounted (kept alive by `mobile_app_shell.dart`'s
/// `IndexedStack`, so in practice that means the app's lifetime). The first
/// time the Contacts tab is actually *opened* (visible — `tabIndex ==
/// [_contactsTabIndex]`, checked both at construction and on every later
/// transition), it calls `load()` (disk first, then a background server
/// refresh — §1: "no user action beyond opening Contacts"); every
/// *subsequent* time it becomes visible again, `refresh()` alone (disk is
/// already loaded). Deliberately gated on visibility rather than firing at
/// construction time unconditionally — `IndexedStack` builds every branch
/// immediately regardless of which tab is selected, so an unconditional
/// `load()` here would start a real directory refresh for every shell
/// mount everywhere in the app, including screens that never visit
/// Contacts at all. [tabIndex] is a [ValueListenable] rather than a plain
/// constructor bool because a `Navigator`'s `onGenerateRoute` only re-runs
/// when a *new* route is pushed, not on every ancestor rebuild — a bool
/// prop set from `_index == 1` at the shell's build time would never
/// change once this branch's root route exists. `directory_providers.dart`
/// is TASK-104's territory, not this task's to add a shared "tab open"
/// provider to, so the shell's own stable notifier is threaded down
/// instead.
class ContactsTabScreen extends ConsumerStatefulWidget {
  const ContactsTabScreen({
    super.key,
    required this.onSelectTarget,
    this.tabIndex,
  });

  final ValueChanged<TalkTarget> onSelectTarget;

  /// The shell's current tab index; Contacts is index 1. `null` in tests
  /// that mount this screen standalone — then it is simply always
  /// "visible" (an initial `load()` still fires; there is nothing to
  /// transition into).
  final ValueListenable<int>? tabIndex;

  @override
  ConsumerState<ContactsTabScreen> createState() => _ContactsTabScreenState();
}

class _ContactsTabScreenState extends ConsumerState<ContactsTabScreen> {
  static const _contactsTabIndex = 1;

  ContactsListController? _controller;
  ContactsController? _boundTo;
  int? _lastIndex;
  bool _hasLoaded = false;

  bool get _isVisible =>
      widget.tabIndex == null || widget.tabIndex!.value == _contactsTabIndex;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.tabIndex?.value;
    widget.tabIndex?.addListener(_onIndexChanged);
  }

  @override
  void didUpdateWidget(covariant ContactsTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tabIndex, widget.tabIndex)) {
      oldWidget.tabIndex?.removeListener(_onIndexChanged);
      widget.tabIndex?.addListener(_onIndexChanged);
    }
  }

  void _onIndexChanged() {
    final current = widget.tabIndex!.value;
    final wasVisible = _lastIndex == _contactsTabIndex;
    final isVisible = current == _contactsTabIndex;
    _lastIndex = current;
    if (isVisible && !wasVisible) {
      _loadOrRefresh();
    }
  }

  void _loadOrRefresh() {
    final controller = _controller;
    if (controller == null) return;
    if (_hasLoaded) {
      unawaited(controller.refresh());
    } else {
      _hasLoaded = true;
      unawaited(controller.load());
    }
  }

  @override
  void dispose() {
    widget.tabIndex?.removeListener(_onIndexChanged);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  ContactsListController _controllerFor(
    ContactsController contacts,
    DirectoryClient directory,
  ) {
    if (_boundTo != contacts) {
      unawaited(_controller?.dispose());
      _boundTo = contacts;
      _hasLoaded = false;
      _controller = ContactsListController(
        contactsController: contacts,
        directoryClient: directory,
      );
      if (_isVisible) _loadOrRefresh();
    }
    return _controller!;
  }

  @override
  Widget build(BuildContext context) {
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
          controller: _controllerFor(controller, directory),
          onSelectTarget: (ContactRowVm contact) =>
              unawaited(_selectContact(ref, contact, widget.onSelectTarget)),
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
    onSelectTarget(talkTargetFromContact(contact: contact, roomId: roomId));
  }
}

/// Pins the TASK-101 contract: a contact [TalkTarget.id] **is**
/// [ContactRowVm.pk] (unpadded base64url of the 32-byte Ed25519 key).
/// [RadioSessionController.switchTarget] reads that id as `peer_pk`.
/// Do not invent a second identifier field.
TalkTarget talkTargetFromContact({
  required ContactRowVm contact,
  required String roomId,
}) {
  return TalkTarget(
    kind: TalkTargetKind.contact,
    id: contact.pk,
    name: contact.callsign,
    roomId: roomId,
    memberPeerIds: <String>[contact.pk],
  );
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
