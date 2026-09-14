import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/directory_providers.dart';
import 'package:keryx/app_shell/incoming_call.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/rooms/derivation.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_list_controller.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';
import 'package:keryx/services/directory/directory.dart';
import 'package:keryx/services/linked/token_client.dart';

import '../services/directory/fakes/fake_directory_server.dart';
import '../services/directory/fakes/fake_presence_transport.dart';
import '../services/directory/fakes/stateful_directory_fake.dart';
import 'journey_harness.dart';

/// TASK-106 gate: an in-memory [ContactsRepository] so the receive-side
/// gate can seed exactly one known contact (A) for B without
/// `shared_preferences` plumbing.
class _SingleContactRepository implements ContactsRepository {
  _SingleContactRepository(this.contact);
  final Contact contact;

  @override
  Future<List<Contact>> loadContacts() async => [contact];
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

void main() {
  // `TestWidgetsFlutterBinding` (pulled in by flutter_test) stubs every
  // `dart:io` HttpClient at 400. The journey talks to a real loopback
  // `FakeDirectoryServer` — same seam as
  // `test/app_shell/directory_enrolment_test.dart` /
  // `test/regression/real_composition_test.dart`.
  HttpOverrides.global = null;

  group('stateful directory fake refusals', () {
    late FakeDirectoryServer server;
    late StatefulDirectoryFake fake;
    late IdentityKeyPair aliceKeys;
    late IdentityKeyPair bobKeys;
    late DirectoryClient alice;
    late DirectoryClient bob;
    late TokenClient aliceToken;

    String alicePk() => encodeUnpaddedBase64Url(aliceKeys.publicKey);
    String bobPk() => encodeUnpaddedBase64Url(bobKeys.publicKey);

    setUp(() async {
      server = await FakeDirectoryServer.start();
      fake = StatefulDirectoryFake();
      server.responder = fake.respond;
      aliceKeys = await IdentityKeyPair.generate();
      bobKeys = await IdentityKeyPair.generate();
      alice = DirectoryClient(baseUrl: server.baseUrl, keyPair: aliceKeys);
      bob = DirectoryClient(baseUrl: server.baseUrl, keyPair: bobKeys);
      aliceToken = TokenClient(baseUrl: server.baseUrl, signer: aliceKeys);
    });

    tearDown(() async {
      alice.close();
      bob.close();
      aliceToken.close();
      await server.close();
    });

    test('POST /v2/identity is an idempotent upsert for the same callsign',
        () async {
      final first = await alice.registerIdentity('ALFA-1');
      expect(first.pk, alicePk());
      expect(first.callsign, 'ALFA-1');
      final second = await alice.registerIdentity('ALFA-1');
      expect(second.pk, first.pk);
      expect(fake.identities[alicePk()], 'ALFA-1');
    });

    test('POST /v2/identity refuses identity_exists on a callsign change',
        () async {
      await alice.registerIdentity('ALFA-1');
      expect(
        () => alice.registerIdentity('ALFA-2'),
        throwsA(
          isA<DirectoryException>().having(
            (e) => e.code,
            'code',
            DirectoryErrorCode.identityExists,
          ),
        ),
      );
    });

    test('POST /v2/contacts/requests refuses 401 unknown_identity', () async {
      await bob.registerIdentity('BRAVO-7');
      expect(
        () => alice.sendContactRequest(bobPk()),
        throwsA(
          isA<DirectoryException>().having(
            (e) => e.code,
            'code',
            DirectoryErrorCode.unknownIdentity,
          ),
        ),
      );
    });

    test('POST /v2/contacts/requests refuses 404 not_found', () async {
      await alice.registerIdentity('ALFA-1');
      expect(
        () => alice.sendContactRequest(bobPk()),
        throwsA(
          isA<DirectoryException>().having(
            (e) => e.code,
            'code',
            DirectoryErrorCode.notFound,
          ),
        ),
      );
    });

    test('POST /v2/contacts/requests refuses 409 already_pending', () async {
      await alice.registerIdentity('ALFA-1');
      await bob.registerIdentity('BRAVO-7');
      await alice.sendContactRequest(bobPk());
      expect(
        () => alice.sendContactRequest(bobPk()),
        throwsA(
          isA<DirectoryException>().having(
            (e) => e.code,
            'code',
            DirectoryErrorCode.alreadyPending,
          ),
        ),
      );
    });

    test('POST /v2/contacts/requests refuses 409 already_contacts', () async {
      await alice.registerIdentity('ALFA-1');
      await bob.registerIdentity('BRAVO-7');
      await alice.sendContactRequest(bobPk());
      await bob.acceptContactRequest(alicePk());
      expect(
        () => alice.sendContactRequest(bobPk()),
        throwsA(
          isA<DirectoryException>().having(
            (e) => e.code,
            'code',
            DirectoryErrorCode.alreadyContacts,
          ),
        ),
      );
    });

    test('POST /token refuses 401 unknown_identity first', () async {
      expect(
        () => aliceToken.requestToken(
          roomId: 'ABCDEFGHIJKLMNOP',
          callsign: 'ALFA-1',
        ),
        throwsA(
          isA<TokenRequestException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.detail, 'detail', 'unknown_identity'),
        ),
      );
    });

    test('POST /token without peer_pk refuses 403 not_member', () async {
      await alice.registerIdentity('ALFA-1');
      expect(
        () => aliceToken.requestToken(
          roomId: 'ABCDEFGHIJKLMNOP',
          callsign: 'ALFA-1',
        ),
        throwsA(
          isA<TokenRequestException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.detail, 'detail', 'not_member'),
        ),
      );
    });

    test('POST /token with peer_pk of a non-contact refuses 403 not_contacts',
        () async {
      await alice.registerIdentity('ALFA-1');
      await bob.registerIdentity('BRAVO-7');
      expect(
        () => aliceToken.requestToken(
          roomId: 'ABCDEFGHIJKLMNOP',
          callsign: 'ALFA-1',
          peerPublicKey: bobKeys.publicKey,
        ),
        throwsA(
          isA<TokenRequestException>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.detail, 'detail', 'not_contacts'),
        ),
      );
    });

    test('POST /token with peer_pk of a contact provisions the DirectRoom',
        () async {
      await alice.registerIdentity('ALFA-1');
      await bob.registerIdentity('BRAVO-7');
      await alice.sendContactRequest(bobPk());
      await bob.acceptContactRequest(alicePk());
      const roomId = 'ABCDEFGHIJKLMNOP';
      final token = await aliceToken.requestToken(
        roomId: roomId,
        callsign: 'ALFA-1',
        peerPublicKey: bobKeys.publicKey,
      );
      expect(token.token, isNotEmpty);
      expect(fake.directRoomFor(alicePk(), bobPk()), roomId);
    });
  });

  group('two-phone journey', () {
    late JourneyHarness harness;

    setUp(() async {
      harness = await JourneyHarness.start();
    });

    tearDown(() async {
      await harness.close();
    });

    test('gate 1 — A boots and registers (POST /v2/identity)', () async {
      await harness.phoneA.boot();
      final enrolment =
          await harness.phoneA.container.read(identityEnrolmentProvider.future);
      expect(enrolment.outcome, IdentityEnrolmentOutcome.registered);
      expect(enrolment.isEnrolled, isTrue);
      expect(
        harness.server.requests
            .where((r) => r.method == 'POST' && r.path == '/v2/identity'),
        isNotEmpty,
      );
      expect(harness.directory.identities[harness.phoneA.pk], 'ALFA-1');
    });

    test('gate 2 — B boots and registers (POST /v2/identity)', () async {
      await harness.phoneB.boot();
      final enrolment =
          await harness.phoneB.container.read(identityEnrolmentProvider.future);
      expect(enrolment.outcome, IdentityEnrolmentOutcome.registered);
      expect(harness.directory.identities[harness.phoneB.pk], 'BRAVO-7');
    });

    test("gate 3 — A pastes B's ID → pending_out on A", () async {
      await harness.phoneA.boot();
      await harness.phoneB.boot();
      final contacts = await harness.phoneA.container
          .read(contactsControllerProvider.future);
      expect(contacts, isNotNull);
      final directory = await harness.phoneA.container
          .read(directoryClientProvider.future);
      final list = ContactsListController(
        contactsController: contacts!,
        directoryClient: directory!,
      );
      final parsed = await list.sendRequestFromId(harness.phoneB.idLink.qrPayload);
      expect(parsed, isA<ContactIdParsed>());
      expect(
        contacts.pendingSnapshot.single.pk,
        harness.phoneB.pk,
      );
      expect(
        contacts.pendingSnapshot.single.direction,
        ContactRequestDirection.outgoing,
      );
      final me = await directory.getMe();
      expect(me.pendingOut.single.toPk, harness.phoneB.pk);
    });

    test(
      'gate 4 — A GET /me after the request still shows pending_out',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        final contacts = await harness.phoneA.container
            .read(contactsControllerProvider.future);
        final directory = await harness.phoneA.container
            .read(directoryClientProvider.future);
        await ContactsListController(
          contactsController: contacts!,
          directoryClient: directory!,
        ).sendRequestFromId(harness.phoneB.idLink.qrPayload);
        final me = await directory.getMe();
        expect(me.pendingOut, hasLength(1));
        expect(me.pendingOut.single.toPk, harness.phoneB.pk);
      },
    );

    test(
      'gate 5 — B GET /me (server truth) lists A in pending_in',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        final aContacts = await harness.phoneA.container
            .read(contactsControllerProvider.future);
        final aDir = await harness.phoneA.container
            .read(directoryClientProvider.future);
        await ContactsListController(
          contactsController: aContacts!,
          directoryClient: aDir!,
        ).sendRequestFromId(harness.phoneB.idLink.qrPayload);
        final bDir = await harness.phoneB.container
            .read(directoryClientProvider.future);
        final me = await bDir!.getMe();
        expect(me.pendingIn.single.fromPk, harness.phoneA.pk);
        expect(me.pendingIn.single.callsign, 'ALFA-1');
      },
    );

    test(
      'gate 6 — B refreshes and sees the request',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        final aContacts = await harness.phoneA.container
            .read(contactsControllerProvider.future);
        final aDir = await harness.phoneA.container
            .read(directoryClientProvider.future);
        await ContactsListController(
          contactsController: aContacts!,
          directoryClient: aDir!,
        ).sendRequestFromId(harness.phoneB.idLink.qrPayload);

        final bContacts = await harness.phoneB.container
            .read(contactsControllerProvider.future);
        await ContactsListController(
          contactsController: bContacts!,
          directoryClient:
              (await harness.phoneB.container.read(directoryClientProvider.future))!,
        ).load();
        expect(
          bContacts.pendingSnapshot.where(
            (p) =>
                p.pk == harness.phoneA.pk &&
                p.direction == ContactRequestDirection.incoming,
          ),
          isNotEmpty,
          reason: 'B must see A incoming after load() refreshes from the server',
        );
      },
    );

    test(
      'gate 7 — B accepts → both list each other as contacts',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        final aContacts = await harness.phoneA.container
            .read(contactsControllerProvider.future);
        final aDir = await harness.phoneA.container
            .read(directoryClientProvider.future);
        await ContactsListController(
          contactsController: aContacts!,
          directoryClient: aDir!,
        ).sendRequestFromId(harness.phoneB.idLink.qrPayload);

        final bContacts = await harness.phoneB.container
            .read(contactsControllerProvider.future);
        final bList = ContactsListController(
          contactsController: bContacts!,
          directoryClient:
              (await harness.phoneB.container.read(directoryClientProvider.future))!,
        );
        await bList.load();
        await bList.accept(harness.phoneA.pk);
        await aContacts.refreshFromServer();
        await bContacts.refreshFromServer();
        expect(
          aContacts.contactsSnapshot.map((c) => c.pk),
          contains(harness.phoneB.pk),
        );
        expect(
          bContacts.contactsSnapshot.map((c) => c.pk),
          contains(harness.phoneA.pk),
        );
      },
    );

    test(
      'gate 8 — A selects B → /token carries peer_pk, DirectRoom provisioned, SetTransport(relay)',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        harness.directory.seedContact(harness.phoneA.pk, harness.phoneB.pk);

        final roomId = await deriveDirectRoom(
          myKeyPair: harness.phoneA.identity.keyPair!,
          theirEdwardsPublicKey: harness.phoneB.identity.keyPair!.publicKey,
        );
        await harness.phoneA.session.switchTarget(
          TalkTarget(
            kind: TalkTargetKind.contact,
            id: harness.phoneB.pk,
            name: 'BRAVO-7',
            roomId: roomId,
            memberPeerIds: [harness.phoneB.identity.peerId],
          ),
          memberPeerIds: [harness.phoneB.identity.peerId],
        );

        final tokenPosts = harness.server.requests
            .where((r) => r.method == 'POST' && r.path == '/token')
            .toList();
        expect(tokenPosts, isNotEmpty);
        expect(tokenPosts.last.bodyJson?['peer_pk'], harness.phoneB.pk);
        expect(
          harness.directory.directRoomFor(harness.phoneA.pk, harness.phoneB.pk),
          roomId,
        );
        expect(harness.phoneA.radioState.transport, Transport.relay);
        expect(harness.phoneA.liveKit.connectCalls, isNotEmpty);
      },
    );

    test(
      'gate 8b — B selects A → same DirectRoom id (§5.4 symmetry)',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        harness.directory.seedContact(harness.phoneA.pk, harness.phoneB.pk);

        final roomA = await deriveDirectRoom(
          myKeyPair: harness.phoneA.identity.keyPair!,
          theirEdwardsPublicKey: harness.phoneB.identity.keyPair!.publicKey,
        );
        final roomB = await deriveDirectRoom(
          myKeyPair: harness.phoneB.identity.keyPair!,
          theirEdwardsPublicKey: harness.phoneA.identity.keyPair!.publicKey,
        );
        expect(roomA, roomB);

        await harness.phoneA.session.switchTarget(
          TalkTarget(
            kind: TalkTargetKind.contact,
            id: harness.phoneB.pk,
            name: 'BRAVO-7',
            roomId: roomA,
          ),
          memberPeerIds: const [],
        );
        await harness.phoneB.session.switchTarget(
          TalkTarget(
            kind: TalkTargetKind.contact,
            id: harness.phoneA.pk,
            name: 'ALFA-1',
            roomId: roomB,
          ),
          memberPeerIds: const [],
        );
        expect(
          harness.directory.directRoomFor(harness.phoneA.pk, harness.phoneB.pk),
          roomA,
        );
        expect(harness.phoneB.radioState.transport, Transport.relay);
      },
    );

    test(
      'gate PTT-after-select — A presses and releases PTT after selecting B; '
      'no throw, host engine is the controller engine, TX phase observed',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        harness.directory.seedContact(harness.phoneA.pk, harness.phoneB.pk);

        final roomId = await deriveDirectRoom(
          myKeyPair: harness.phoneA.identity.keyPair!,
          theirEdwardsPublicKey: harness.phoneB.identity.keyPair!.publicKey,
        );
        await harness.phoneA.session.switchTarget(
          TalkTarget(
            kind: TalkTargetKind.contact,
            id: harness.phoneB.pk,
            name: 'BRAVO-7',
            roomId: roomId,
            memberPeerIds: const [],
          ),
          memberPeerIds: const [],
        );
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final host = harness.phoneA.radioHost;
        expect(
          host.current.floorEngine,
          same(harness.phoneA.session.floorEngine),
        );

        expect(() => host.pressPtt(), returnsNormally);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(harness.phoneA.session.floorEngine.isTransmitting, isTrue);
        expect(harness.phoneA.radioState.phase, RadioPhase.tx);

        expect(() => host.releasePtt(), returnsNormally);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(harness.phoneA.session.floorEngine.isTransmitting, isFalse);
        expect(harness.phoneA.radioState.phase, isNot(RadioPhase.tx));
      },
    );

    test(
      'receive-side — B hears A without selecting A',
      () async {
        await harness.phoneA.boot();
        await harness.phoneB.boot();
        harness.directory.seedContact(harness.phoneA.pk, harness.phoneB.pk);

        final roomId = await deriveDirectRoom(
          myKeyPair: harness.phoneB.identity.keyPair!,
          theirEdwardsPublicKey: harness.phoneA.identity.keyPair!.publicKey,
        );

        // `journey_harness.dart` (TASK-107's `Owned_Paths`, not this
        // task's) wires each phone's session-level providers, but never
        // app_shell's presence/contacts composition — nothing in it needs
        // to, until now. Rather than touch that file, this gate builds a
        // second, narrow `ProviderContainer` for B's app_shell layer that
        // reuses the *exact same* `KeryxRadioHost` instance
        // (`harness.phoneB.radioHost`) the real session lives on, so a
        // `switchTarget` call from this container dispatches into B's real
        // `RadioSessionController`/`radioStateProvider`, exactly as
        // `mobile_app_shell.dart`'s own composition root would.
        final transport = FakePresenceTransport();
        final contactsController = ContactsController(
          directoryClient: DirectoryClient(
            baseUrl: harness.server.baseUrl,
            keyPair: harness.phoneB.identity.keyPair!,
          ),
          repository: _SingleContactRepository(
            Contact(pk: harness.phoneA.pk, callsign: 'ALFA-1'),
          ),
        );
        await contactsController.loadFromDisk();
        final bAppShell = ProviderContainer(
          overrides: <Override>[
            radioHostProvider.overrideWithValue(harness.phoneB.radioHost),
            identityProvider.overrideWith((ref) async => harness.phoneB.identity),
            contactsControllerProvider.overrideWith((ref) async => contactsController),
            presenceClientProvider.overrideWith(
              (ref) async => PresenceClient(
                baseUrl: harness.server.baseUrl,
                keyPair: harness.phoneB.identity.keyPair!,
                transport: transport,
              ),
            ),
          ],
        );
        addTearDown(bAppShell.dispose);

        bAppShell.read(incomingCallProvider); // arms the listener
        final presence = await bAppShell.read(presenceClientProvider.future);
        await presence!.start();
        expect(bAppShell.read(currentTargetProvider), isNull);

        // A starts talking — the same wire shape `talking_presence.dart`
        // sends on local TX start.
        transport.lastSocket!.deliver(
          jsonEncode({'pk': harness.phoneA.pk, 'status': 'available', 'talking': true, 'since': 1}),
        );
        // TASK-112: a fixed 8-iteration `Duration.zero` microtask drain is
        // not a deadline, it's a guess at how many microtask hops the real
        // chain needs — usually enough in isolation, but under
        // `--concurrency=2` (other test files sharing the isolate) extra
        // hops can land between `currentTargetProvider` being set (the
        // synchronous half of the receive-side handler) and `switchTarget`
        // actually completing session adoption (the awaited half), and 8
        // is occasionally not enough: the assertions below then read
        // `radioState.transport` before the relay session has adopted,
        // landing on the LOCAL-boot default (`Transport.direct`) instead.
        // Poll for the real terminal condition instead of guessing a hop
        // count — the same fix applied to the analogous flake found and
        // fixed in `test/app_shell/directory_providers_test.dart` (TASK-111).
        for (
          var i = 0;
          i < 50 && harness.phoneB.radioState.transport != Transport.relay;
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        expect(bAppShell.read(currentTargetProvider)?.target.id, harness.phoneA.pk);
        expect(bAppShell.read(currentTargetProvider)?.target.roomId, roomId);
        expect(
          harness.directory.directRoomFor(harness.phoneA.pk, harness.phoneB.pk),
          roomId,
        );
        expect(harness.phoneB.radioState.transport, Transport.relay);
      },
    );
  });
}
