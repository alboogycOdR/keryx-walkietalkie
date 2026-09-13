/// Starts presence exactly once the app's directory enrolment reaches
/// `registered` (Technical §4.3: "Client opens the WS after boot with a
/// signed hello"). `PresenceClient.start()` (TASK-105 root cause) had zero
/// callers before this file — nothing ever opened the socket.
///
/// Mirrors `mobile_app_shell.dart`'s host-boot pattern: a plain [Provider]
/// read once at shell init (`ref.read(presenceBootstrapProvider)`), not
/// `watch`ed, so this file is the single owner of "presence has started"
/// for the app's lifetime and never restarts it once begun. Reconnect and
/// backoff after the socket drops are already handled *inside*
/// [PresenceClient] itself — this only decides the single moment to call
/// `start()` the first time.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'directory_providers.dart';

/// Watches [registrationStatusProvider] and calls
/// `PresenceClient.start()` (via [presenceClientProvider]) the first time
/// (and only the first time) it reports [RegistrationRegistered]. A later
/// transition back through [RegistrationOffline]/[RegistrationFailed] and
/// re-registration does not call `start()` again — the client's own
/// internal reconnect loop is what survives a transient drop; this
/// provider's job is only the initial boot.
final presenceBootstrapProvider = Provider<void>((ref) {
  var started = false;

  Future<void> maybeStart(RegistrationStatus status) async {
    if (started) return;
    if (status is! RegistrationRegistered) return;
    started = true;
    final presence = await ref.read(presenceClientProvider.future);
    await presence?.start();
  }

  ref.listen<RegistrationStatus>(
    registrationStatusProvider,
    (previous, next) => unawaited(maybeStart(next)),
    fireImmediately: true,
  );
});
