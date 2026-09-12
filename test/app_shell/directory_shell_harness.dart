import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/services/directory/directory.dart';

import '../services/directory/fakes/fake_directory_server.dart';
import 'fake_radio_host.dart';

/// A [FakeDirectoryServer]-backed harness for `lib/app_shell/**` widget
/// tests that need Contacts/Groups to actually reach a directory backend
/// rather than render the "needs a relay address" empty state — mirrors
/// TASK-090/091's own `FakeDirectoryServer` pattern
/// (`test/services/directory/fakes/fake_directory_server.dart`), composed
/// the way `directory_providers.dart` composes the real client/controller
/// stack, but with [directoryClientProvider]/[presenceClientProvider]/
/// [identityProvider] overridden directly rather than derived from
/// `settings.relayUrl` — this harness's job is to prove the shell wires a
/// real `DirectoryClient` through to Contacts/Groups, not to re-prove
/// [directoryBaseUri]'s own derivation (that is `directory_providers.dart`'s
/// own unit-level concern).
class DirectoryShellHarness {
  DirectoryShellHarness._(this.server, this.keyPair, this.identity);

  final FakeDirectoryServer server;
  final IdentityKeyPair keyPair;
  final DeviceIdentity identity;

  static Future<DirectoryShellHarness> start({String callsign = 'BRAVO-7'}) async {
    final server = await FakeDirectoryServer.start();
    final keyPair = await IdentityKeyPair.generate();
    final identity = DeviceIdentity(
      installUuid: '00000000-0000-4000-8000-000000000000',
      peerId: derivePeerId(keyPair.publicKey),
      callsign: Callsign.parse(callsign),
      keyPair: keyPair,
    );
    return DirectoryShellHarness._(server, keyPair, identity);
  }

  Future<void> close() => server.close();

  /// Builds a [ProviderContainer] wired the same way [pump] wires its
  /// `ProviderScope`, so a test can `container.read(...)` a real controller
  /// directly — e.g. to call `ContactsController.refreshFromServer()` the
  /// way a real pull-to-refresh would, since nothing in
  /// `lib/app_shell/**`'s own `Owned_Paths` auto-refreshes on tab mount
  /// (that refresh trigger is TASK-090/091's own controller-wiring
  /// territory, not this task's).
  ProviderContainer buildContainer({required FakeRadioHost host}) {
    final directoryClient = DirectoryClient(baseUrl: server.baseUrl, keyPair: keyPair);
    final presenceClient = PresenceClient(baseUrl: server.baseUrl, keyPair: keyPair);
    return ProviderContainer(
      overrides: <Override>[
        radioHostProvider.overrideWithValue(host),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        identityProvider.overrideWith((ref) async => identity),
        directoryClientProvider.overrideWith((ref) async => directoryClient),
        presenceClientProvider.overrideWith((ref) async => presenceClient),
      ],
    );
  }

  /// Builds the widget tree for a shell test that needs a live directory,
  /// backed by [container] (build one via [buildContainer] so the test can
  /// also read providers directly).
  Widget pumpWithContainer({
    required ProviderContainer container,
    required Widget home,
    ThemeData? theme,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme ?? keryxUxThemeData(), home: home),
    );
  }
}
