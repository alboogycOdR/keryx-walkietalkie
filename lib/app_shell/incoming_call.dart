/// TASK-106 receive side (Technical §4.3, §5.4, §6.4; Design §2.1, §4): a
/// contact reporting `talking: true` over presence, while this device has
/// no current target (or an idle one), becomes the current target and its
/// room is joined — the "both select each other first" requirement TASK-106
/// removes.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/contacts/contacts.dart' show Contact;
import 'package:keryx/core/presentation/talk_target.dart'
    show TalkTarget, TalkTargetKind;
import 'package:keryx/core/radio_host/radio_host_contract.dart'
    show RadioTargetSwitcher;
import 'package:keryx/core/rooms/derivation.dart' show deriveDirectRoom;
import 'package:keryx/core/state/radio_state.dart' show RadioPhase;
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/services/directory/directory.dart' show PresenceUpdate;

import 'contacts_tab_screen.dart' show decodeUnpaddedBase64Url;
import 'directory_providers.dart';
import 'radio_host_provider.dart';

/// Watches [presenceUpdatesProvider] and, on a *contact's* `talking: true`
/// event, auto-selects and joins that contact — mirrors
/// `mobile_app_shell.dart`'s own `_selectTarget` two-step (presentation
/// write + `RadioTargetSwitcher.switchTarget`) exactly, since this is the
/// same "select a target" action, just triggered by presence instead of a
/// tap. Read once (never watched) at shell composition, same shape as
/// `presence_bootstrap.dart`/`talking_presence.dart`.
final incomingCallProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<PresenceUpdate>>(
    presenceUpdatesProvider,
    (previous, next) {
      final update = next.valueOrNull;
      if (update == null || update.talking != true) return;
      unawaited(_maybeJoin(ref, update.pk));
    },
  );
});

/// State precedence (Design §4): never steals an active TX or a
/// deliberately selected different target — proceeds only when there is no
/// current target at all, or the radio is otherwise idle (not mid
/// tx/txRequest/rxActive on whatever target is already selected).
Future<void> _maybeJoin(Ref ref, String pk) async {
  final current = ref.read(currentTargetProvider);
  final radioState = ref.read(radioStateProvider);
  if (current != null && radioState.phase != RadioPhase.idle) return;
  if (current?.target.id == pk) return; // already the current target

  final contactsController = await ref.read(contactsControllerProvider.future);
  if (contactsController == null) return;
  Contact? contact;
  for (final c in contactsController.contactsSnapshot) {
    if (c.pk == pk) {
      contact = c;
      break;
    }
  }
  if (contact == null) return; // talking peer isn't a known contact

  final identity = await ref.read(identityProvider.future);
  final keyPair = identity.keyPair;
  if (keyPair == null) return;
  final theirPublicKey = decodeUnpaddedBase64Url(contact.pk);
  if (theirPublicKey == null) return;
  final roomId = await deriveDirectRoom(
    myKeyPair: keyPair,
    theirEdwardsPublicKey: theirPublicKey,
  );
  final target = TalkTarget(
    kind: TalkTargetKind.contact,
    id: contact.pk,
    name: contact.callsign,
    roomId: roomId,
    memberPeerIds: <String>[contact.pk],
  );

  // Re-check precedence after the awaits above — a TX/explicit selection
  // may have started while this resolved.
  final currentAfter = ref.read(currentTargetProvider);
  final radioStateAfter = ref.read(radioStateProvider);
  if (currentAfter != null && radioStateAfter.phase != RadioPhase.idle) return;

  ref.read(currentTargetProvider.notifier).state = TalkTargetSelection(target);
  final host = ref.read(radioHostProvider);
  if (host is RadioTargetSwitcher) {
    unawaited((host as RadioTargetSwitcher).switchTarget(target));
  }
}
