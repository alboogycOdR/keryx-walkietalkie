import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';

import '../services/directory/fakes/fake_directory_server.dart';

/// TASK-099 — Technical §6.4: `directoryClientProvider` is fully built and
/// unit-tested in isolation (`test/services/directory/directory_client_test.dart`)
/// but was never wired into any real call path. This file closes that gap
/// the same way `test/regression/real_composition_test.dart` closes the
/// analogous `radioHostProvider` gap (TASK-058 §9): it drives the REAL
/// `directoryClientProvider` — never overridden wholesale — against a fake
/// backend, so the actual `registerIdentity` call this task adds is what
/// gets exercised, not a hand-built controller-level stand-in for
/// `DirectoryClient`.
///
/// Every other test that needs a working directory
/// (`DirectoryShellHarness`, `real_composition_test.dart`) overrides
/// `directoryClientProvider` wholesale with an already-constructed
/// `DirectoryClient`, which is the right call when the subject under test
/// is Contacts/Groups UI — but it would skip straight past the code this
/// task actually adds. Since `directoryBaseUri` unconditionally upgrades
/// the derived URL to `https` (Technical precedent: mirrors
/// `KeryxSettings.resolvedTokenServiceUrl`) and this repo's only fake
/// backend (`FakeDirectoryServer`) is plain HTTP — there being no HTTP
/// mocking package here, same as every other `directory`/`linked` test —
/// this test instead overrides only `directoryBaseUriResolverProvider`
/// (the narrow seam `directory_providers.dart` exposes for exactly this),
/// pointing `directoryClientProvider`'s real body at the fake server's
/// plain-HTTP `baseUrl` directly. Every other line inside
/// `directoryClientProvider` — reading settings/identity, constructing the
/// real `DirectoryClient`, calling `registerIdentity`, the try/catch
/// swallow, returning the client — is the real, unmodified provider body.
void main() {
  late FakeDirectoryServer server;
  late IdentityKeyPair keyPair;
  late DeviceIdentity identity;

  setUp(() async {
    // `contactsControllerProvider`/`groupsControllerProvider` both read
    // `SharedPreferences.getInstance()` once `directory` resolves non-null
    // — mock its platform channel or that future never resolves under
    // `flutter test` (same fix as `real_composition_test.dart`).
    SharedPreferences.setMockInitialValues(<String, Object>{});

    server = await FakeDirectoryServer.start();
    keyPair = await IdentityKeyPair.generate();
    identity = DeviceIdentity(
      installUuid: '00000000-0000-4000-8000-000000000000',
      peerId: derivePeerId(keyPair.publicKey),
      callsign: Callsign.parse('BRAVO-7'),
      keyPair: keyPair,
    );
  });

  tearDown(() async {
    await server.close();
  });

  Future<ProviderContainer> buildContainer() async {
    final store = InMemorySettingsStore();
    // The value here never actually reaches `directoryBaseUri` in this
    // test — `directoryBaseUriResolverProvider` is overridden below — but
    // it must still be a URL `Uri.tryParse` accepts with a non-empty host,
    // since `settings.relayUrl` is read for real.
    await store.write(
      SettingsRepository.storageKey,
      jsonEncode(const KeryxSettings().copyWith(relayUrl: 'wss://relay.invalid/ws').toJson()),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(store),
        identityProvider.overrideWith((ref) async => identity),
        directoryBaseUriResolverProvider.overrideWithValue((relayUrl) => server.baseUrl),
      ],
    );
    return container;
  }

  test(
    'directoryClientProvider registers identity before returning the '
    'client, and before any dependent provider can reach the server',
    () async {
      final container = await buildContainer();
      addTearDown(container.dispose);

      final client = await container.read(directoryClientProvider.future);
      expect(client, isNotNull);
      expect(server.requests, hasLength(1));
      expect(server.requests.single.method, 'POST');
      expect(server.requests.single.path, '/v2/identity');
      expect(server.requests.single.bodyJson, {'callsign': 'BRAVO-7'});

      // Resolving every dependent provider must not itself add a second
      // server request — they only ever consume the already-registered
      // client `directoryClientProvider` handed back.
      await container.read(presenceClientProvider.future);
      await container.read(contactsControllerProvider.future);
      await container.read(groupsControllerProvider.future);
      expect(
        server.requests,
        hasLength(1),
        reason: 'building contacts/groups/presence must not itself contact the server',
      );
    },
  );

  test(
    'a repeat provider rebuild with the same callsign does not throw '
    '(server upsert is idempotent)',
    () async {
      final container = await buildContainer();
      addTearDown(container.dispose);

      final first = await container.read(directoryClientProvider.future);
      expect(first, isNotNull);
      expect(server.requests, hasLength(1));

      // Simulate a provider rebuild (e.g. a dependency invalidation) with
      // the exact same identity/callsign still in scope.
      container.invalidate(directoryClientProvider);
      final second = await container.read(directoryClientProvider.future);
      expect(second, isNotNull);
      expect(
        server.requests,
        hasLength(2),
        reason: 'the rebuild must have re-registered rather than throwing or skipping',
      );
      expect(server.requests.last.bodyJson, {'callsign': 'BRAVO-7'});
    },
  );

  test(
    'a registration failure still yields dependent providers resolving '
    'without throwing',
    () async {
      server.responder = (_) => const DirectoryFakeResponse(
        statusCode: 500,
        body: {'error': 'server_error'},
      );

      final container = await buildContainer();
      addTearDown(container.dispose);

      // The failed registerIdentity call must be caught and logged inside
      // directoryClientProvider, never rethrown to this await.
      final client = await container.read(directoryClientProvider.future);
      expect(client, isNotNull);
      expect(server.requests, hasLength(1));

      // Every dependent provider still resolves cleanly off the back of
      // that (still-usable) client — none of them crash the provider chain.
      final presence = await container.read(presenceClientProvider.future);
      final contacts = await container.read(contactsControllerProvider.future);
      final groups = await container.read(groupsControllerProvider.future);
      expect(presence, isNotNull);
      expect(contacts, isNotNull);
      expect(groups, isNotNull);
    },
  );
}
