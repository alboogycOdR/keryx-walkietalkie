import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/protocol/protocol.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:keryx/services/platform/platform.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

import '../services/directory/fakes/fake_directory_server.dart';

/// v2 Technical §6.4 — the enrolment *lifecycle* proof.
///
/// Field defect (2026-09-12): `registerIdentity` was correct, tested, and
/// wired — into a lazy provider only the Contacts/Groups tabs ever read. A
/// fresh install that went straight to Talk therefore never registered, and
/// the boot-time LINKED `/token` mint was refused `unknown_identity` no
/// matter what. The test that "passed" for that fix only proved
/// `registerIdentity` gets called *somewhere*; it never asked *when*, or
/// *whether the Talk-only path reaches it at all*. This file asks exactly
/// that.
///
/// What is real here: `identityEnrolmentProvider`, `DirectoryClient`, its
/// `dart:io` `HttpClient`, a real loopback `HttpServer`
/// (`FakeDirectoryServer`), and a real `KeryxRadioHost` running its real
/// boot. What is faked: only the five native seams `KeryxRadioHost` takes
/// as constructor injection (audio sink, permission gate, foreground
/// service, session host, identity) — the same rule
/// `test/regression/real_composition_test.dart` follows.
///
/// What is deliberately NEVER touched: `directoryClientProvider`,
/// `contactsControllerProvider`, `groupsControllerProvider`,
/// `presenceClientProvider` — asserted via `ProviderContainer.exists`. If
/// enrolment ever slides back into being a side effect of those, the
/// ordering assertions here go red.

class _NullFloorTransport implements FloorTransport {
  final _incoming = StreamController<FloorMessage>.broadcast();

  @override
  Stream<FloorMessage> get incoming => _incoming.stream;

  @override
  void send(FloorMessage message) {}

  void dispose() => unawaited(_incoming.close());
}

class _SessionHostFake implements SessionHost {
  _SessionHostFake() {
    _engine.updateRoster({'peer-under-test'});
  }

  final _NullFloorTransport _transport = _NullFloorTransport();
  late final FloorEngine _engine = FloorEngine(
    localPeerId: 'peer-under-test',
    transport: _transport,
    clock: const WallClock(),
    tot: const Duration(seconds: 60),
    busyLockout: true,
    callsign: 'BRAVO-7',
  );
  final _stations = StreamController<List<StationInfo>>.broadcast();

  bool startCalled = false;

  @override
  FloorEngine get floorEngine => _engine;

  @override
  Stream<List<StationInfo>> get stations => _stations.stream;

  @override
  Future<void> start() async {
    startCalled = true;
  }

  @override
  Future<void> dispose() async {
    _engine.dispose();
    _transport.dispose();
    await _stations.close();
  }
}

class _PermissionGateFake implements FacePermissionGate {
  @override
  Future<FacePermissionOutcome> ensureMicrophone() async =>
      FacePermissionOutcome.granted;

  @override
  Future<FacePermissionOutcome> ensureNotifications() async =>
      FacePermissionOutcome.granted;

  @override
  Future<FacePermissionOutcome> ensureNearbyWifiDevices() async =>
      FacePermissionOutcome.granted;
}

/// A [FakeDirectoryServer.responder] that answers `POST /v2/identity` with
/// a well-formed registration and everything else with `200 {}`.
DirectoryFakeResponse _healthyDirectory(RecordedDirectoryRequest request) {
  if (request.method == 'POST' && request.path == '/v2/identity') {
    return DirectoryFakeResponse(
      statusCode: 200,
      body: {'pk': 'server-echo', 'callsign': request.bodyJson?['callsign']},
    );
  }
  return const DirectoryFakeResponse(statusCode: 200, body: {});
}

void main() {
  late FakeDirectoryServer server;
  late DeviceIdentity identity;

  setUp(() async {
    server = await FakeDirectoryServer.start();
    server.responder = _healthyDirectory;
    final keyPair = await IdentityKeyPair.generate();
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

  Future<ProviderContainer> buildContainer({String relayUrl = 'wss://relay.invalid/ws'}) async {
    final store = InMemorySettingsStore();
    await store.write(
      SettingsRepository.storageKey,
      // TASK-104: relayUrl now has a non-empty baked-in default, so an
      // empty value is only honoured as "no relay configured" when marked
      // as an explicit user clear (mirrors `SettingsRepository.save`'s own
      // derivation) — otherwise `fromJson` would substitute the default.
      jsonEncode(
        const KeryxSettings()
            .copyWith(relayUrl: relayUrl, relayUrlUserCleared: relayUrl.isEmpty)
            .toJson(),
      ),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        settingsStoreProvider.overrideWithValue(store),
        identityProvider.overrideWith((ref) async => identity),
        // Honour "no relay configured" exactly like the real
        // `directoryBaseUri` does (null for an empty/hostless relay); only
        // the scheme/host substitution is faked.
        directoryBaseUriResolverProvider.overrideWithValue(
          (relayUrl) => relayUrl.isEmpty ? null : server.baseUrl,
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Builds a real [KeryxRadioHost] exactly as `radioHostProvider` does —
  /// its `ensureDirectoryEnrolment` is the real `identityEnrolmentProvider`
  /// read off [container] — with only the native seams faked.
  ({KeryxRadioHost host, _SessionHostFake session, RadioState Function() state, List<int> requestsWhenSessionBuilt})
      buildHost(ProviderContainer container) {
    final session = _SessionHostFake();
    final requestsWhenSessionBuilt = <int>[];
    var state = const RadioState.off();
    void Function(RadioState? previous, RadioState next)? radioListener;

    final host = KeryxRadioHost(
      sessionFactory: ({
        required String localPeerId,
        required String callsign,
        required KeryxSettings settings,
        required void Function(RadioEvent event) dispatch,
      }) {
        // The ordering witness: how many directory requests the server had
        // already SERVED at the instant the host asked for a session.
        requestsWhenSessionBuilt.add(server.requests.length);
        return session;
      },
      audioSinkFactory: () async => RecordingAudioSink(),
      audioSinkDisposer: (_) async {},
      identityFactory: () async => identity,
      permissionGateFactory: _PermissionGateFake.new,
      radioServiceFactory: () =>
          ChannelRadioServiceController(platform: FakeRadioServicePlatform()),
      loadSettings: () => container.read(settingsProvider.future),
      dispatch: (event) {
        final previous = state;
        state = const RadioReducer().reduce(state, event);
        radioListener?.call(previous, state);
      },
      readRadioState: () => state,
      listenRadioState: (onChange, {bool fireImmediately = false}) {
        radioListener = onChange;
        if (fireImmediately) onChange(null, state);
        return () => radioListener = null;
      },
      listenSettings: (_) => () {},
      ensureDirectoryEnrolment: () => container.read(identityEnrolmentProvider.future),
    );
    return (
      host: host,
      session: session,
      state: () => state,
      requestsWhenSessionBuilt: requestsWhenSessionBuilt,
    );
  }

  test(
    'a Talk-only boot registers with the directory BEFORE the session '
    'starts, with Contacts/Groups/presence providers never built',
    () async {
      final container = await buildContainer();
      final h = buildHost(container);

      await h.host.start();
      addTearDown(h.host.dispose);

      expect(h.state().phase, RadioPhase.idle);
      expect(h.session.startCalled, isTrue);

      // Exactly one directory request, and it is the registration.
      expect(
        server.requests.map((r) => '${r.method} ${r.path}').toList(),
        ['POST /v2/identity'],
      );
      expect(server.requests.single.bodyJson, {'callsign': 'BRAVO-7'});

      // ORDER: the registration had already been served when the host built
      // its session — the guarantee the field defect lacked.
      expect(h.requestsWhenSessionBuilt, [1]);

      // The enrolment the host awaited is the app's single memoised one.
      final enrolment = await container.read(identityEnrolmentProvider.future);
      expect(enrolment.outcome, IdentityEnrolmentOutcome.registered);
      expect(enrolment.isEnrolled, isTrue);
      expect(server.requests, hasLength(1),
          reason: 'reading the enrolment again must not re-register');

      // Nothing on the Talk path built the lazy directory-backed providers.
      expect(container.exists(directoryClientProvider), isFalse);
      expect(container.exists(presenceClientProvider), isFalse);
      expect(container.exists(contactsControllerProvider), isFalse);
      expect(container.exists(groupsControllerProvider), isFalse);
    },
  );

  test(
    'a directory that is down never throws into the host: boot still '
    'reaches idle, the session still starts, and the outcome is recorded',
    () async {
      server.responder = (_) => const DirectoryFakeResponse(
            statusCode: 500,
            body: {'error': 'server_error'},
          );
      final container = await buildContainer();
      final h = buildHost(container);

      await h.host.start();
      addTearDown(h.host.dispose);

      expect(h.state().phase, RadioPhase.idle);
      expect(h.session.startCalled, isTrue);
      expect(h.host.current.sessionFailureKind, isNull,
          reason: 'an enrolment failure is not a session failure');

      final enrolment = await container.read(identityEnrolmentProvider.future);
      expect(enrolment.outcome, IdentityEnrolmentOutcome.failed);
      expect(enrolment.error, isA<DirectoryException>());
      expect(enrolment.client, isNotNull,
          reason: 'dependents still get a client so they fail with the '
              "server's own code, not a provider-chain crash");
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'identity_exists (key known under an old callsign) is resolved through '
    'the rename route, not by re-registering forever',
    () async {
      server.responder = (request) {
        if (request.method == 'POST' && request.path == '/v2/identity') {
          return const DirectoryFakeResponse(
            statusCode: 409,
            body: {'error': 'identity_exists'},
          );
        }
        return const DirectoryFakeResponse(statusCode: 200, body: {});
      };
      final container = await buildContainer();

      final enrolment = await container.read(identityEnrolmentProvider.future);

      expect(enrolment.outcome, IdentityEnrolmentOutcome.renamed);
      expect(enrolment.isEnrolled, isTrue);
      expect(
        server.requests.map((r) => '${r.method} ${r.path}').toList(),
        ['POST /v2/identity', 'PATCH /v2/identity/callsign'],
      );
      expect(server.requests.last.bodyJson, {'callsign': 'BRAVO-7'});
    },
  );

  test(
    'directoryClientProvider and presenceClientProvider both draw on the '
    'same single enrolment — one registration, one client, no race',
    () async {
      final container = await buildContainer();

      // Presence first — it must not be able to reach the server ahead of
      // registration, and it must not trigger a second registration.
      final presence = await container.read(presenceClientProvider.future);
      expect(presence, isNotNull);
      expect(
        server.requests.map((r) => '${r.method} ${r.path}').toList(),
        ['POST /v2/identity'],
      );

      final client = await container.read(directoryClientProvider.future);
      final enrolment = await container.read(identityEnrolmentProvider.future);
      expect(client, same(enrolment.client));
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'no relay configured: enrolment is not applicable, nothing is sent, '
    'and the host boots to idle exactly as before',
    () async {
      final container = await buildContainer(relayUrl: '');
      final h = buildHost(container);

      await h.host.start();
      addTearDown(h.host.dispose);

      expect(h.state().phase, RadioPhase.idle);
      expect(server.requests, isEmpty);
      final enrolment = await container.read(identityEnrolmentProvider.future);
      expect(enrolment.outcome, IdentityEnrolmentOutcome.notApplicable);
      expect(enrolment.client, isNull);
      expect(await container.read(directoryClientProvider.future), isNull);
    },
  );
}
