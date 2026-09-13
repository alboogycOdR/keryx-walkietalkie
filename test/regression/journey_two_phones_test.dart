import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/directory_providers.dart';
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
import '../services/directory/fakes/stateful_directory_fake.dart';
import 'journey_harness.dart';

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
      skip:
          'gate 6 — ContactsController.refreshFromServer() has no callers; un-skip when TASK-105 lands',
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
      skip:
          'gate 7 — B accepts; ContactsController.refreshFromServer() has no callers; un-skip when TASK-105 lands',
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
      () async {},
      skip:
          'receive-side — no auto-join; un-skip when TASK-106 lands',
    );
  });
}
