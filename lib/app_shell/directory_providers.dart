import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/groups/groups.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/talk_target.dart' show PeerPresence, TalkTarget;
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/services/directory/directory.dart';

import 'app_lifecycle.dart';

const _logName = 'keryx.app_shell.directory';

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

/// Seam so a test can substitute how [directoryClientProvider]/
/// [presenceClientProvider] derive the directory's base URL from
/// `settings.relayUrl`, without ever overriding those providers themselves
/// wholesale (this task's own test needs the REAL `directoryClientProvider`
/// body — including its `registerIdentity` call — to run, but has no way to
/// stand up a TLS-terminating fake backend for [directoryBaseUri]'s forced
/// `https` upgrade). Same seam shape as `radio_host_provider.dart`'s
/// constructor-injected platform factories (TASK-048) — production always
/// gets the real [directoryBaseUri]; only
/// `test/app_shell/directory_providers_test.dart` overrides this.
final directoryBaseUriResolverProvider =
    Provider<Uri? Function(String relayUrl)>((ref) => directoryBaseUri);

/// The local device's v2 identity. A plain [FutureProvider] (not `.family`,
/// not autoDispose) — exactly one identity exists for the app's lifetime,
/// same convention as [radioHostProvider]'s single instance.
final identityProvider = FutureProvider<DeviceIdentity>((ref) {
  return IdentityRepository(SecureIdentityStore()).loadOrCreate();
});

final _sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// How the app's single directory enrolment concluded (see
/// [identityEnrolmentProvider]).
enum IdentityEnrolmentOutcome {
  /// No relay configured (or no v2 key pair) — there is no directory to
  /// enrol with; every directory-backed feature stays in its "no relay"
  /// empty state. Not an error.
  notApplicable,

  /// `POST /v2/identity` succeeded (or was a no-op upsert for an identity
  /// the directory already knew under this callsign).
  registered,

  /// The directory knew this public key under a *different* callsign
  /// (`identity_exists`, 409) — the local callsign had been renamed — and
  /// `PATCH /v2/identity/callsign` brought the directory in line. Enrolled.
  renamed,

  /// Registration (and, where attempted, the rename) failed — network, a
  /// down directory, `callsign_taken`, anything. The client is still handed
  /// out so callers fail honestly with the server's own code rather than
  /// crashing the provider chain; the next enrolment (next settings change,
  /// or app start) retries.
  failed,
}

/// Result of [identityEnrolmentProvider]: the app's one [DirectoryClient]
/// (null iff [outcome] is [IdentityEnrolmentOutcome.notApplicable]) plus how
/// enrolment went. Immutable; a fresh instance per provider (re)build.
class IdentityEnrolment {
  const IdentityEnrolment._(this.client, this.outcome, this.error);

  const IdentityEnrolment.notApplicable()
    : this._(null, IdentityEnrolmentOutcome.notApplicable, null);

  final DirectoryClient? client;
  final IdentityEnrolmentOutcome outcome;

  /// The failure behind [IdentityEnrolmentOutcome.failed]; null otherwise.
  final Object? error;

  bool get isEnrolled =>
      outcome == IdentityEnrolmentOutcome.registered ||
      outcome == IdentityEnrolmentOutcome.renamed;
}

/// **The single owner of "this device's identity is known to the
/// directory"** (v2 Technical §6.4: `load identity → open directory session
/// → …`; §4.2 `POST /v2/identity`, `PATCH /v2/identity/callsign`).
///
/// Every signed request in the app — the LINKED `/token` mint that
/// `RadioSessionController` makes at boot, contact requests, presence's
/// signed WebSocket handshake, groups — is refused by `token-svc` with
/// `unknown_identity` (401) unless the caller's public key is registered
/// first. That guarantee therefore has to come from exactly one place that
/// every one of those paths draws on, and it has to run *before* the first
/// of them, not whenever the user happens to open the Contacts tab:
///
/// - [directoryClientProvider] and [presenceClientProvider] both await this
///   and reuse its client, so the directory-backed tabs never race it.
/// - `radioHostProvider` injects `() => ref.read(identityEnrolmentProvider
///   .future)` as `KeryxRadioHost.ensureDirectoryEnrolment`, and the host
///   awaits it at the top of every session start (boot and every
///   settings-triggered rebuild). That is what makes enrolment *eager*: the
///   host boots on app start unconditionally, so registration completes
///   before the boot-time LINKED join even when nothing else in the app has
///   touched the directory yet.
///
/// Watches `settingsProvider`, so a relay-URL change re-enrols against the
/// new directory; otherwise memoised for the app's lifetime like every other
/// provider in this file. The server-side upsert is idempotent (same pubkey
/// + same callsign → no-op success), so re-running is always safe.
///
/// **Never throws.** Directory bootstrap must not block reaching Talk
/// (LOCAL needs no directory at all) — a failure is recorded in
/// [IdentityEnrolment.outcome]/[IdentityEnrolment.error], logged, and the
/// still-usable client is handed out so dependents fail with the server's
/// own honest code instead of a provider-chain crash.
///
/// History: this replaces the enrolment TASK-099 (commit `48747a9`) put
/// inside [directoryClientProvider], which was correct in isolation but
/// lazy — nothing on the Talk tab reads that provider, so a fresh install
/// that went straight to Talk never registered at all, and the boot-time
/// LINKED join was rejected regardless (field-confirmed 2026-09-12).
final identityEnrolmentProvider = FutureProvider<IdentityEnrolment>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final identity = await ref.watch(identityProvider.future);
  final keyPair = identity.keyPair;
  final resolveBase = ref.watch(directoryBaseUriResolverProvider);
  final base = resolveBase(settings.relayUrl);
  if (base == null || keyPair == null) {
    return const IdentityEnrolment.notApplicable();
  }
  final client = DirectoryClient(baseUrl: base, keyPair: keyPair);
  ref.onDispose(client.close);

  final callsign = identity.callsign.value;
  Object? registerError;
  try {
    await client.registerIdentity(callsign);
    return IdentityEnrolment._(client, IdentityEnrolmentOutcome.registered, null);
  } on Object catch (error) {
    // Deliberately no `rethrow` anywhere in here: a `rethrow` inside an
    // `on` clause leaves the whole `try`, it does not fall through to a
    // later `on Object` — this provider must never throw.
    registerError = error;
  }

  if (registerError is DirectoryException &&
      registerError.code == DirectoryErrorCode.identityExists) {
    // Same public key, different callsign: the user renamed locally. The
    // directory's rename route is the contract for exactly this (§4.2
    // `PATCH /v2/identity/callsign`); registering again would 409 forever.
    try {
      await client.patchCallsign(callsign);
      return IdentityEnrolment._(client, IdentityEnrolmentOutcome.renamed, null);
    } on Object catch (renameError, stack) {
      developer.log(
        'identity enrolment: directory knows this key under another callsign '
        'and the rename failed; continuing unenrolled',
        name: _logName,
        error: renameError,
        stackTrace: stack,
      );
      return IdentityEnrolment._(client, IdentityEnrolmentOutcome.failed, renameError);
    }
  }

  developer.log(
    'identity enrolment failed; continuing unenrolled',
    name: _logName,
    error: registerError,
  );
  return IdentityEnrolment._(client, IdentityEnrolmentOutcome.failed, registerError);
});

/// `null` whenever no relay is configured yet (fresh install before
/// Settings/onboarding sets one) — every provider below stays `null` too
/// rather than throwing, so Contacts/Groups render their real empty states
/// instead of crashing the shell (Technical §6.4: directory bootstrap must
/// not block reaching Talk).
///
/// The client is [identityEnrolmentProvider]'s — this provider adds no
/// behaviour of its own, it only exposes the already-enrolled client to the
/// contacts/groups composition below.
final directoryClientProvider = FutureProvider<DirectoryClient?>((ref) async {
  final enrolment = await ref.watch(identityEnrolmentProvider.future);
  return enrolment.client;
});

final presenceClientProvider = FutureProvider<PresenceClient?>((ref) async {
  // The presence WebSocket's signed handshake is refused with
  // `unknown_identity` (4401) for an unregistered key, exactly like every
  // REST route — so presence draws the same enrolment guarantee first and
  // never races it (see [identityEnrolmentProvider]).
  await ref.watch(identityEnrolmentProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  final identity = await ref.watch(identityProvider.future);
  final keyPair = identity.keyPair;
  final resolveBase = ref.watch(directoryBaseUriResolverProvider);
  final base = resolveBase(settings.relayUrl);
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

/// v2 (Owner requirements 2026-09-13): the retried, *visible* registration
/// state consumed by onboarding and Settings → Identity.
///
/// Deliberately layered on top of [identityEnrolmentProvider] rather than
/// replacing its shape: that provider's `IdentityEnrolment`/
/// `IdentityEnrolmentOutcome` contract is the seam `radioHostProvider`
/// (`lib/core/radio_host/**`, frozen territory) and
/// `test/app_shell/directory_enrolment_test.dart` depend on — one attempt,
/// awaited once, never retried by itself. [registrationStatusProvider] adds
/// the exponential-backoff retry, the app-foreground trigger and the
/// richer, UI-facing state without touching any of that.
sealed class RegistrationStatus {
  const RegistrationStatus();
}

/// No relay configured (or no v2 key pair yet) — mirrors
/// [IdentityEnrolmentOutcome.notApplicable].
class RegistrationUnregistered extends RegistrationStatus {
  const RegistrationUnregistered();
}

/// An enrolment attempt is in flight (first attempt, `registerNow()`, a
/// backoff retry, or a foreground-triggered retry).
class RegistrationInProgress extends RegistrationStatus {
  const RegistrationInProgress();
}

/// Enrolled — mirrors [IdentityEnrolmentOutcome.registered] and
/// [IdentityEnrolmentOutcome.renamed], which are the same success state from
/// the UI's point of view.
class RegistrationRegistered extends RegistrationStatus {
  const RegistrationRegistered({required this.callsign, this.shortCode});
  final String callsign;
  final String? shortCode;
}

/// The last attempt failed with a transport failure (never reached the
/// server) — treated as "offline", not a hard error, and retried
/// automatically. [retryAt] is when the next automatic retry is scheduled.
class RegistrationOffline extends RegistrationStatus {
  const RegistrationOffline({required this.retryAt});
  final DateTime retryAt;
}

/// The directory itself answered with an error code (e.g. `callsign_taken`).
/// Still retried on the same backoff — the directory may recover, and a
/// `callsign_taken` in particular clears the moment the user renames — but
/// surfaced distinctly so the UI can show a named reason.
class RegistrationFailed extends RegistrationStatus {
  const RegistrationFailed({required this.code});
  final DirectoryErrorCode code;
}

/// Backoff ladder: 1, 2, 4, 8, 16, 32, 60(capped) seconds (Decision, ORCH
/// owner-approved 2026-09-13).
const _registrationBackoffFloor = Duration(seconds: 1);
const _registrationBackoffCap = Duration(seconds: 60);

/// The state machine behind [registrationStatusProvider].
class RegistrationStatusController extends Notifier<RegistrationStatus> {
  Timer? _retryTimer;
  Duration _nextBackoff = _registrationBackoffFloor;
  StreamSubscription<void>? _foregroundSubscription;

  /// Test-only: the delay the currently-pending retry [Timer] was scheduled
  /// with, or `null` when no retry is pending. Lets a test assert the
  /// backoff ladder (1, 2, 4 … 60 s cap) without needing a real or virtual
  /// clock for `Timer` itself.
  @visibleForTesting
  Duration? get debugPendingRetryDelay => _retryTimer == null ? null : _pendingDelay;
  Duration? _pendingDelay;

  /// Test-only: fires the pending retry immediately, exactly as the real
  /// `Timer` callback would once its delay elapsed — without waiting for
  /// real time to pass.
  @visibleForTesting
  void debugFirePendingRetry() {
    if (_retryTimer == null) return;
    _retryTimer!.cancel();
    _retryTimer = null;
    _pendingDelay = null;
    state = const RegistrationInProgress();
    ref.invalidate(identityEnrolmentProvider);
  }

  @override
  RegistrationStatus build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      unawaited(_foregroundSubscription?.cancel());
    });

    // `ref.read`, not `ref.watch`: this Notifier manages its own mutable
    // backoff/timer state across enrolment updates via `ref.listen` below —
    // watching either provider here would rebuild (and reset) that state
    // every time either one changes.
    _foregroundSubscription = ref
        .read(appForegroundProvider)
        .listen((_) => _onForeground());

    ref.listen<AsyncValue<IdentityEnrolment>>(
      identityEnrolmentProvider,
      (previous, next) => _applyEnrolment(next),
    );

    return _statusFor(ref.read(identityEnrolmentProvider)) ??
        const RegistrationInProgress();
  }

  /// Re-runs enrolment right now (Settings → Identity's "Register now"),
  /// resetting the backoff ladder since this is a fresh, user-initiated
  /// attempt rather than a scheduled retry.
  void registerNow() {
    _cancelRetry();
    _nextBackoff = _registrationBackoffFloor;
    state = const RegistrationInProgress();
    ref.invalidate(identityEnrolmentProvider);
  }

  void _onForeground() {
    if (state is RegistrationOffline || state is RegistrationFailed) {
      _cancelRetry();
      _nextBackoff = _registrationBackoffFloor;
      state = const RegistrationInProgress();
      ref.invalidate(identityEnrolmentProvider);
    }
  }

  void _applyEnrolment(AsyncValue<IdentityEnrolment> value) {
    final status = _statusFor(value);
    if (status == null) return; // still loading; keep showing in-progress
    state = status;
    if (status is RegistrationRegistered || status is RegistrationUnregistered) {
      _cancelRetry();
      _nextBackoff = _registrationBackoffFloor;
    } else if (status is RegistrationOffline || status is RegistrationFailed) {
      _scheduleRetry();
    }
  }

  RegistrationStatus? _statusFor(AsyncValue<IdentityEnrolment> value) {
    // A refresh-in-progress (e.g. right after `ref.invalidate`) is often an
    // `AsyncData`/`AsyncError` with `isLoading: true` that still carries the
    // *previous* value/error, not a fresh `AsyncLoading` — `.when()` alone
    // routes purely by runtime type, so it would otherwise re-process the
    // stale previous outcome as if it were new (double-scheduling a retry
    // for a failure that already happened). Checking `isLoading` first
    // means a refresh always reports in-progress until the new value lands.
    if (value.isLoading) return const RegistrationInProgress();
    return value.when(
      loading: () => const RegistrationInProgress(),
      error: (error, _) => _failureStatusFor(error),
      data: (enrolment) {
        switch (enrolment.outcome) {
          case IdentityEnrolmentOutcome.notApplicable:
            return const RegistrationUnregistered();
          case IdentityEnrolmentOutcome.registered:
          case IdentityEnrolmentOutcome.renamed:
            final identity = ref.read(identityProvider).valueOrNull;
            return RegistrationRegistered(
              callsign: identity?.callsign.value ?? '',
              shortCode: identity?.shortCode,
            );
          case IdentityEnrolmentOutcome.failed:
            return _failureStatusFor(enrolment.error);
        }
      },
    );
  }

  RegistrationStatus _failureStatusFor(Object? error) {
    if (error is DirectoryException) {
      if (error.isTransportFailure) {
        return RegistrationOffline(retryAt: DateTime.now().add(_nextBackoff));
      }
      return RegistrationFailed(code: error.code);
    }
    // Anything else (a bug, an unexpected throw) is treated as offline —
    // retried the same way rather than sticking the user in a dead end.
    return RegistrationOffline(retryAt: DateTime.now().add(_nextBackoff));
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _nextBackoff;
    _pendingDelay = delay;
    _retryTimer = Timer(delay, () {
      _pendingDelay = null;
      state = const RegistrationInProgress();
      ref.invalidate(identityEnrolmentProvider);
    });
    final doubled = delay * 2;
    _nextBackoff = doubled > _registrationBackoffCap ? _registrationBackoffCap : doubled;
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _pendingDelay = null;
  }
}

final registrationStatusProvider =
    NotifierProvider<RegistrationStatusController, RegistrationStatus>(
  RegistrationStatusController.new,
);
