import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keryx/app_shell/app_lifecycle.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/talk_target.dart' show PeerPresence;
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/services/directory/directory.dart';

import '../services/directory/fakes/fake_directory_server.dart';
import '../services/directory/fakes/fake_presence_transport.dart';

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
      // the exact same identity/callsign still in scope. Registration now
      // lives in `identityEnrolmentProvider` (the single owner —
      // `directoryClientProvider` only re-exposes its client), so that is
      // the provider a rebuild must re-run; invalidating the client provider
      // alone deliberately re-registers nothing.
      container.invalidate(identityEnrolmentProvider);
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

  group('registrationStatusProvider', () {
    // TASK-104 (B): the retried, visible state layered on top of
    // `identityEnrolmentProvider` — that provider's own contract (this
    // file's tests above, and `directory_enrolment_test.dart`) is untouched;
    // these tests exercise the retry/backoff/foreground wrapper only.
    //
    // `_ServerBox` lets a test swap in a fresh `FakeDirectoryServer` (e.g.
    // "the directory comes back") mid-test: `directoryBaseUriResolverProvider`
    // is fixed at container construction, but the closure below reads
    // `box.server` afresh on every call, so mutating the box after
    // construction is enough.
    Future<ProviderContainer> buildStatusContainer(
      _ServerBox box, {
      String relayUrl = 'wss://relay.invalid/ws',
      StreamController<void>? foreground,
    }) async {
      final store = InMemorySettingsStore();
      await store.write(
        SettingsRepository.storageKey,
        jsonEncode(const KeryxSettings().copyWith(relayUrl: relayUrl).toJson()),
      );
      // Real `AppForegroundObserver` needs a live `WidgetsBinding`
      // (`TestWidgetsFlutterBinding`), which in turn makes every real
      // `dart:io` HTTP request in this suite return a stub 400 — fatal for
      // these tests' real `FakeDirectoryServer` traffic. A plain controlled
      // stream exercises exactly the same `_onForeground` code path without
      // ever touching `WidgetsBinding`.
      final foregroundController = foreground ?? StreamController<void>.broadcast();
      final container = ProviderContainer(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(store),
          identityProvider.overrideWith((ref) async => identity),
          directoryBaseUriResolverProvider.overrideWithValue(
            (relayUrl) => relayUrl.isEmpty ? null : box.uri,
          ),
          appForegroundProvider.overrideWithValue(foregroundController.stream),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'a transport failure lands offline with a scheduled backoff retry; '
      'the backoff ladder doubles until the cap; a subsequent success lands '
      'registered and cancels the retry',
      () async {
        // A transport failure (never reached the server) is what the real
        // HTTP client raises against a closed port — close the server
        // entirely for this rather than have it answer with an error code
        // (that is `RegistrationFailed`, covered separately below). Keep
        // the (now-dead) port in the box so `directoryBaseUriResolverProvider`
        // still resolves to *something* — an unreachable port, not `null`
        // (which would mean "no relay configured", i.e. `notApplicable`).
        final deadPort = server.baseUrl;
        await server.close();
        final box = _ServerBox(deadPort);

        final container = await buildStatusContainer(box);
        final notifier = container.read(registrationStatusProvider.notifier);

        container.read(registrationStatusProvider);
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(registrationStatusProvider), isA<RegistrationOffline>());
        expect(notifier.debugPendingRetryDelay, const Duration(seconds: 1));

        notifier.debugFirePendingRetry();
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(registrationStatusProvider), isA<RegistrationOffline>());
        expect(notifier.debugPendingRetryDelay, const Duration(seconds: 2));

        notifier.debugFirePendingRetry();
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(notifier.debugPendingRetryDelay, const Duration(seconds: 4));

        // Bring the directory back and let the next retry succeed.
        final revived = await FakeDirectoryServer.start();
        addTearDown(revived.close);
        revived.responder = (request) => DirectoryFakeResponse(
          statusCode: 200,
          body: {'pk': 'server-echo', 'callsign': request.bodyJson?['callsign']},
        );
        box.uri = revived.baseUrl;

        notifier.debugFirePendingRetry();
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);

        final status = container.read(registrationStatusProvider);
        expect(status, isA<RegistrationRegistered>());
        expect((status as RegistrationRegistered).callsign, 'BRAVO-7');
        expect(notifier.debugPendingRetryDelay, isNull,
            reason: 'a successful registration must cancel any pending retry');
      },
    );

    test(
      'a directory error response (callsign_taken) is exposed as '
      'RegistrationFailed with the server code, and still schedules a retry',
      () async {
        server.responder = (_) => const DirectoryFakeResponse(
          statusCode: 409,
          body: {'error': 'callsign_taken'},
        );
        final container = await buildStatusContainer(_ServerBox.forServer(server));
        final notifier = container.read(registrationStatusProvider.notifier);

        container.read(registrationStatusProvider);
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);

        final status = container.read(registrationStatusProvider);
        expect(status, isA<RegistrationFailed>());
        expect((status as RegistrationFailed).code, DirectoryErrorCode.callsignTaken);
        expect(notifier.debugPendingRetryDelay, const Duration(seconds: 1));
      },
    );

    test(
      'an app-foreground event triggers an immediate retry while offline, '
      'and nothing while registered',
      () async {
        final deadPort = server.baseUrl;
        await server.close();
        final box = _ServerBox(deadPort);
        final foreground = StreamController<void>.broadcast();
        addTearDown(foreground.close);
        final container = await buildStatusContainer(box, foreground: foreground);
        final notifier = container.read(registrationStatusProvider.notifier);

        container.read(registrationStatusProvider);
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(registrationStatusProvider), isA<RegistrationOffline>());
        expect(notifier.debugPendingRetryDelay, isNotNull,
            reason: 'the automatic backoff retry is still pending');

        final revived = await FakeDirectoryServer.start();
        addTearDown(revived.close);
        revived.responder = (request) => DirectoryFakeResponse(
          statusCode: 200,
          body: {'pk': 'server-echo', 'callsign': request.bodyJson?['callsign']},
        );
        box.uri = revived.baseUrl;

        // A real resume event, through the exact `Stream<void>` the real
        // `AppForegroundObserver` exposes — no need to wait for the
        // scheduled backoff timer at all.
        foreground.add(null);
        // The stream event (and so `_onForeground`'s `invalidate`) is
        // delivered asynchronously — give it a turn before reading
        // `.future`, or this reads the *old*, already-resolved future.
        await Future<void>.delayed(Duration.zero);
        await container.read(identityEnrolmentProvider.future);
        await Future<void>.delayed(Duration.zero);
        expect(container.read(registrationStatusProvider), isA<RegistrationRegistered>());
        expect(notifier.debugPendingRetryDelay, isNull,
            reason: 'a successful registration must cancel any pending retry');

        // Once registered, a further resume must not schedule or fire a
        // retry — there is nothing to retry.
        final requestsBefore = revived.requests.length;
        foreground.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(revived.requests.length, requestsBefore,
            reason: 'a resume while already registered must not re-register');
      },
    );

    test('registerNow() resets the backoff and re-attempts immediately', () async {
      server.responder = (_) => const DirectoryFakeResponse(
        statusCode: 500,
        body: {'error': 'server_error'},
      );
      final container = await buildStatusContainer(_ServerBox.forServer(server));
      final notifier = container.read(registrationStatusProvider.notifier);

      container.read(registrationStatusProvider);
      await container.read(identityEnrolmentProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.debugPendingRetryDelay, const Duration(seconds: 1));
      notifier.debugFirePendingRetry();
      await container.read(identityEnrolmentProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(notifier.debugPendingRetryDelay, const Duration(seconds: 2));

      server.responder = (request) => DirectoryFakeResponse(
        statusCode: 200,
        body: {'pk': 'server-echo', 'callsign': request.bodyJson?['callsign']},
      );
      notifier.registerNow();
      await container.read(identityEnrolmentProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(registrationStatusProvider), isA<RegistrationRegistered>());
    });
  });

  group('presenceByPeerIdProvider (TASK-111)', () {
    // TASK-111: the relay sends no presence roster snapshot on WebSocket
    // connect, so Contacts (which already has each contact's persisted
    // status from `GET /v2/identity/me`) can show a contact Available while
    // Talk/PTT — driven only by live WS events until now — showed the same
    // contact Offline. The fix seeds this projection from
    // `contactsControllerProvider`'s already-loaded snapshot, then keeps
    // applying live updates on top. These two tests are exactly the two
    // acceptance criteria the TASK-111 review found unproven: seeded value
    // shown before any live update arrives (AC1), and a live update still
    // overriding that seed afterward (AC2) — a real regression risk, since
    // `ContactsController` merging live presence into `contactsSnapshot`
    // is a non-local invariant nothing else pins.
    late FakePresenceTransport transport;

    Future<ProviderContainer> buildPresenceContainer({required List<Contact> contacts}) async {
      transport = FakePresenceTransport();
      final myKeyPair = await IdentityKeyPair.generate();
      final directoryClient = DirectoryClient(
        baseUrl: Uri.parse('http://localhost'),
        keyPair: myKeyPair,
      );
      final contactsController = ContactsController(
        directoryClient: directoryClient,
        repository: _SeededContactsRepository(contacts),
      );
      // presenceByPeerIdProvider does a synchronous `ref.read` of
      // contactsControllerProvider, not a `watch` — the snapshot must
      // already be loaded before the presence provider first builds, or
      // the seed is skipped entirely (a disclosed, non-blocking finding
      // from the TASK-111 review; not what these tests are proving).
      await contactsController.loadFromDisk();

      final container = ProviderContainer(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) async => DeviceIdentity(
              installUuid: '00000000-0000-4000-8000-000000000000',
              peerId: derivePeerId(myKeyPair.publicKey),
              callsign: Callsign.parse('ME-1'),
              keyPair: myKeyPair,
            ),
          ),
          contactsControllerProvider.overrideWith((ref) async => contactsController),
          presenceClientProvider.overrideWith(
            (ref) async => PresenceClient(
              baseUrl: Uri.parse('http://localhost'),
              keyPair: myKeyPair,
              transport: transport,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      // `presenceByPeerIdProvider` does a synchronous `ref.read` of
      // `contactsControllerProvider` (not `watch`) the moment it first
      // builds — resolve it first, or the seed silently comes back empty
      // (a disclosed, non-blocking finding from the TASK-111 review; not
      // what these two tests exist to prove).
      await container.read(contactsControllerProvider.future);
      final presence = await container.read(presenceClientProvider.future);
      await presence!.start();
      return container;
    }

    test(
      'AC1: a contact whose only known status is the loaded ContactsController '
      "snapshot is shown with that status, not a hardcoded Offline default",
      () async {
        final container = await buildPresenceContainer(
          contacts: [const Contact(pk: 'peer-1', callsign: 'ZULU-1', status: 'available')],
        );

        final map = await container.read(presenceByPeerIdProvider.future);
        expect(
          map['peer-1'],
          PeerPresence.online,
          reason: 'the persisted snapshot status must seed this projection; '
              'nothing has been received over the live WS yet',
        );
      },
    );

    test(
      'AC2: a live WebSocket presence update received after the seed still '
      'overrides it (the seed must not permanently shadow live updates)',
      () async {
        final container = await buildPresenceContainer(
          contacts: [const Contact(pk: 'peer-1', callsign: 'ZULU-1', status: 'available')],
        );

        // A single listener kept alive for the whole test, set up before
        // any delivery: reading `.future` first and only THEN attaching a
        // separate `.listen()` (as an earlier version of this test did)
        // lets this provider's listener count drop to zero in between,
        // which tears down/restarts its internal `await for` subscription
        // to `presence.updates` — a broadcast stream, so an event
        // delivered into that gap is silently dropped rather than
        // buffered. Keeping one subscription open from the start avoids
        // the gap entirely.
        final updates = <Map<String, PeerPresence>>[];
        final sub = container.listen(
          presenceByPeerIdProvider,
          (_, next) => next.whenData(updates.add),
          fireImmediately: true,
        );
        addTearDown(sub.close);

        // Confirm the seed is in effect first, so this test actually
        // proves an override rather than a value that happened to already
        // be busy.
        for (var i = 0; i < 20 && updates.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(updates.single['peer-1'], PeerPresence.online);

        transport.lastSocket!.deliver(
          jsonEncode({'pk': 'peer-1', 'status': 'busy', 'since': 1}),
        );
        for (var i = 0; i < 20 && updates.last['peer-1'] != PeerPresence.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }

        expect(
          updates.last['peer-1'],
          PeerPresence.busy,
          reason: 'a live update for a contact must override its seeded '
              'snapshot value, not be shadowed by it',
        );
      },
    );
  });
}

/// In-memory [ContactsRepository] pre-loaded with a fixed contact list —
/// mirrors `test/app_shell/incoming_call_test.dart`'s own
/// `_FakeContactsRepository`, kept file-local rather than shared per this
/// project's existing test-double convention.
class _SeededContactsRepository implements ContactsRepository {
  _SeededContactsRepository(this.seed);
  final List<Contact> seed;

  @override
  Future<List<Contact>> loadContacts() async => seed;
  @override
  Future<void> saveContacts(List<Contact> contacts) async {}
  @override
  Future<List<PendingContactRequest>> loadPending() async => const [];
  @override
  Future<void> savePending(List<PendingContactRequest> pending) async {}
  @override
  Future<List<BlockedContact>> loadBlocked() async => const [];
  @override
  Future<void> saveBlocked(List<BlockedContact> blocked) async {}
}

/// A mutable indirection for `directoryBaseUriResolverProvider`'s override
/// closure, which is fixed at [ProviderContainer] construction: a test that
/// needs to move the resolved base URL mid-test (e.g. "the directory comes
/// back") mutates [uri] instead of rebuilding the container.
class _ServerBox {
  _ServerBox(this.uri);
  factory _ServerBox.forServer(FakeDirectoryServer server) => _ServerBox(server.baseUrl);
  Uri? uri;
}
