import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/app_shell/presence_bootstrap.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/services/directory/directory.dart';

import '../services/directory/fakes/fake_presence_transport.dart';

/// Test-only stand-in for [RegistrationStatusController] so a test can
/// drive [registrationStatusProvider] straight to any [RegistrationStatus]
/// transition without wiring a real identity/settings/directory chain —
/// [presenceBootstrapProvider]'s own contract only depends on that
/// provider's *state*, not on how it got there.
class _TestRegistrationStatusController extends RegistrationStatusController {
  @override
  RegistrationStatus build() {
    ref.onDispose(() {});
    return const RegistrationInProgress();
  }

  void setStatus(RegistrationStatus status) => state = status;
}

void main() {
  test('PresenceClient.start() is called exactly once, only after '
      'RegistrationRegistered, and never again on a later flap', () async {
    final transport = FakePresenceTransport();
    final keyPair = await IdentityKeyPair.generate();
    final container = ProviderContainer(
      overrides: [
        registrationStatusProvider.overrideWith(_TestRegistrationStatusController.new),
        presenceClientProvider.overrideWith(
          (ref) async => PresenceClient(
            baseUrl: Uri.parse('http://localhost'),
            keyPair: keyPair,
            transport: transport,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Reading the provider is what `mobile_app_shell.dart` does at shell
    // init — arms the listener without itself starting anything yet.
    container.read(presenceBootstrapProvider);
    await Future<void>.delayed(Duration.zero);
    expect(transport.connectCalls, isEmpty, reason: 'must not start before registered');

    final ctrl = container.read(registrationStatusProvider.notifier)
        as _TestRegistrationStatusController;
    ctrl.setStatus(const RegistrationRegistered(callsign: 'ME'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.connectCalls, hasLength(1));

    // A later drop and re-registration must not restart it a second time —
    // reconnect/backoff after the socket drops is `PresenceClient`'s own
    // internal concern, not this provider's.
    ctrl.setStatus(RegistrationOffline(retryAt: DateTime.now()));
    ctrl.setStatus(const RegistrationRegistered(callsign: 'ME'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(transport.connectCalls, hasLength(1));
  });

  test('never starts while unregistered/offline/failed', () async {
    final transport = FakePresenceTransport();
    final keyPair = await IdentityKeyPair.generate();
    final container = ProviderContainer(
      overrides: [
        registrationStatusProvider.overrideWith(_TestRegistrationStatusController.new),
        presenceClientProvider.overrideWith(
          (ref) async => PresenceClient(
            baseUrl: Uri.parse('http://localhost'),
            keyPair: keyPair,
            transport: transport,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(presenceBootstrapProvider);
    final ctrl = container.read(registrationStatusProvider.notifier)
        as _TestRegistrationStatusController;
    ctrl.setStatus(const RegistrationUnregistered());
    ctrl.setStatus(RegistrationOffline(retryAt: DateTime.now()));
    ctrl.setStatus(const RegistrationFailed(code: DirectoryErrorCode.callsignTaken));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(transport.connectCalls, isEmpty);
  });
}
