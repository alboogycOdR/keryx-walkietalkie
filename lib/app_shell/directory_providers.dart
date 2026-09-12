import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/talk_target.dart' show PeerPresence, TalkTarget;
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/services/directory/directory.dart';

/// v2 (Technical §6.4, TASK-093): the directory/contacts/groups composition
/// root. `lib/core/contacts/**`, `lib/core/groups/**` and
/// `lib/services/directory/**` are all outside this task's `Owned_Paths`
/// (each a different task's territory) — this file only *composes* their
/// already-built, already-tested public constructors, exactly the way
/// `radio_host_provider.dart` composes the audio/session/service factories
/// for `KeryxRadioHost` (TASK-048's own pattern).
///
/// **Disclosed scope decision:** there is no `directoryUrl` field on
/// `KeryxSettings` (`lib/core/settings/settings_model.dart` is frozen
/// territory, not this task's to extend) and the spec does not name one.
/// Mirroring `KeryxSettings.resolvedTokenServiceUrl`'s own precedent
/// (derives an HTTPS origin from the `wss://` relay URL), [directoryBaseUri]
/// derives the v2 directory's HTTPS origin the same way. A relay-side route
/// under a different path is an ops/relay-compose concern, not a client
/// wiring one — flagged here for ORCH/a successor task if that assumption
/// is ever wrong.
Uri? directoryBaseUri(String relayUrl) {
  final relay = Uri.tryParse(relayUrl);
  if (relay == null || relay.host.isEmpty) return null;
  return relay.replace(scheme: 'https', path: '/v2', query: null);
}

/// The local device's v2 identity. A plain [FutureProvider] (not `.family`,
/// not autoDispose) — exactly one identity exists for the app's lifetime,
/// same convention as [radioHostProvider]'s single instance.
final identityProvider = FutureProvider<DeviceIdentity>((ref) {
  return IdentityRepository(SecureIdentityStore()).loadOrCreate();
});

final _sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// `null` whenever no relay is configured yet (fresh install before
/// Settings/onboarding sets one) — every provider below stays `null` too
/// rather than throwing, so Contacts/Groups render their real empty states
/// instead of crashing the shell (Technical §6.4: directory bootstrap must
/// not block reaching Talk).
final directoryClientProvider = FutureProvider<DirectoryClient?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final identity = await ref.watch(identityProvider.future);
  final keyPair = identity.keyPair;
  final base = directoryBaseUri(settings.relayUrl);
  if (base == null || keyPair == null) return null;
  final client = DirectoryClient(baseUrl: base, keyPair: keyPair);
  ref.onDispose(client.close);
  return client;
});

final presenceClientProvider = FutureProvider<PresenceClient?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final identity = await ref.watch(identityProvider.future);
  final keyPair = identity.keyPair;
  final base = directoryBaseUri(settings.relayUrl);
  if (base == null || keyPair == null) return null;
  final client = PresenceClient(baseUrl: base, keyPair: keyPair);
  ref.onDispose(client.dispose);
  return client;
});

final contactsControllerProvider = FutureProvider<ContactsController?>((
  ref,
) async {
  final directory = await ref.watch(directoryClientProvider.future);
  if (directory == null) return null;
  final presence = await ref.watch(presenceClientProvider.future);
  final prefs = await ref.watch(_sharedPreferencesProvider.future);
  final controller = ContactsController(
    directoryClient: directory,
    repository: SharedPreferencesContactsRepository(prefs),
    presenceClient: presence,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final groupsControllerProvider = FutureProvider<GroupsController?>((
  ref,
) async {
  final directory = await ref.watch(directoryClientProvider.future);
  if (directory == null) return null;
  final presence = await ref.watch(presenceClientProvider.future);
  final identity = await ref.watch(identityProvider.future);
  final keyPair = identity.keyPair;
  if (keyPair == null) return null;
  final prefs = await ref.watch(_sharedPreferencesProvider.future);
  final controller = GroupsController(
    directoryClient: directory,
    repository: SharedPreferencesGroupsRepository(prefs),
    keyPair: keyPair,
    presenceClient: presence,
  );
  ref.onDispose(controller.dispose);
  return controller;
});

/// v2 (Design §1 "Current target"): the presentation-layer current Talk
/// target, set whenever a contact or group is selected anywhere in the
/// shell. `null` on a fresh install with no history.
///
/// **Disclosed scope decision:** this only drives the Talk screen's header
/// card, audience computation and ready-ring rule (all presentation,
/// Technical §6.3) — it does not itself call
/// `RadioSessionController.switchTarget`/join a different LiveKit room.
/// `RadioSessionHostV2` (`lib/core/radio_host/radio_session_host_v2.dart`)
/// is the seam Technical §6.4 names for that, but it needs a live
/// `RadioSessionController` instance and `KeryxRadioHost`
/// (`lib/core/radio_host/keryx_radio_host.dart`, frozen territory) has no
/// public accessor for the one it constructs per-session — wiring that
/// through is an `OWNERSHIP_CONFLICT`-shaped gap in `lib/core/radio_host/**`
/// this task cannot close from `lib/app_shell/**` alone. Routed to ORCH as
/// follow-up debt rather than worked around by editing frozen code.
final currentTargetProvider = StateProvider<TalkTargetSelection?>((ref) => null);

/// Presence for every peerId this device currently knows about, merged from
/// both [PresenceClient] streams — kept as one flat map because
/// `TalkScreen.presenceByPeerId` (TASK-092) doesn't care whether a peer is a
/// contact or a group member.
final presenceByPeerIdProvider =
    StreamProvider<Map<String, PeerPresence>>((ref) async* {
  final presence = await ref.watch(presenceClientProvider.future);
  if (presence == null) {
    yield const {};
    return;
  }
  final Map<String, PeerPresence> state = {};
  yield Map.unmodifiable(state);
  await for (final update in presence.updates) {
    state[update.pk] = _presenceFromStatus(update.status);
    yield Map.unmodifiable(state);
  }
});

PeerPresence _presenceFromStatus(String status) => switch (status) {
      'available' => PeerPresence.online,
      'busy' => PeerPresence.busy,
      'dnd' => PeerPresence.dnd,
      _ => PeerPresence.offline,
    };

/// A [TalkTarget] plus whatever this shell needs to re-derive it (kept
/// alongside rather than folded into `TalkTarget` itself, since that type
/// is `lib/core/presentation/**` territory, not this task's to extend).
class TalkTargetSelection {
  const TalkTargetSelection(this.target);
  final TalkTarget target;
}
