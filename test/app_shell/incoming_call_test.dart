import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/app_shell/incoming_call.dart';
import 'package:keryx/core/contacts/contacts.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/presentation/talk_target.dart';
import 'package:keryx/core/radio_host/radio_host_contract.dart' show RadioTargetSwitcher;
import 'package:keryx/core/rooms/derivation.dart' show deriveDirectRoom;
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/services/directory/directory.dart';

import '../services/directory/fakes/fake_presence_transport.dart';
import 'fake_radio_host.dart';

/// In-memory [ContactsRepository] so a test can seed `contactsSnapshot`
/// without `shared_preferences` plumbing — mirrors this file's own
/// `_TestRadioStateController` in spirit (minimum stand-in for the real
/// contract, not the real backing store).
class _FakeContactsRepository implements ContactsRepository {
  _FakeContactsRepository(this.seed);
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

class _TestRadioStateController extends RadioStateController {
  @override
  RadioState build() => const RadioState.off();
  void setState(RadioState next) => state = next;
}

/// Same shape as `mobile_app_shell_test.dart`'s own
/// `_TargetSwitchingFakeRadioHost` — `FakeRadioHost` (shared, not this
/// task's `Owned_Paths`) doesn't implement `RadioTargetSwitcher`.
class _TargetSwitchingFakeRadioHost extends FakeRadioHost implements RadioTargetSwitcher {
  final List<TalkTarget> switchTargetCalls = <TalkTarget>[];
  @override
  Future<void> switchTarget(TalkTarget target) async {
    switchTargetCalls.add(target);
  }
}

void main() {
  late FakePresenceTransport transport;
  late ProviderContainer container;
  late _TargetSwitchingFakeRadioHost host;
  late IdentityKeyPair myKeyPair;
  late IdentityKeyPair theirKeyPair;
  late String theirPk;

  Future<ProviderContainer> build({List<Contact>? contacts}) async {
    transport = FakePresenceTransport();
    myKeyPair = await IdentityKeyPair.generate();
    theirKeyPair = await IdentityKeyPair.generate();
    theirPk = unpaddedBase64Url(theirKeyPair.publicKey);
    host = _TargetSwitchingFakeRadioHost();
    final directoryClient = DirectoryClient(baseUrl: Uri.parse('http://localhost'), keyPair: myKeyPair);
    final contactsController = ContactsController(
      directoryClient: directoryClient,
      repository: _FakeContactsRepository(
        contacts ?? [Contact(pk: theirPk, callsign: 'ZULU-1')],
      ),
    );
    await contactsController.loadFromDisk();

    container = ProviderContainer(
      overrides: [
        radioHostProvider.overrideWithValue(host),
        radioStateProvider.overrideWith(_TestRadioStateController.new),
        identityProvider.overrideWith((ref) async => DeviceIdentity(
              installUuid: '00000000-0000-4000-8000-000000000000',
              peerId: derivePeerId(myKeyPair.publicKey),
              callsign: Callsign.parse('ME-1'),
              keyPair: myKeyPair,
            )),
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
    final presence = await container.read(presenceClientProvider.future);
    await presence!.start();
    return container;
  }

  void deliverTalking(String pk, {bool talking = true}) {
    transport.lastSocket!.deliver(
      jsonEncode({'pk': pk, 'status': 'available', 'talking': talking, 'since': 1}),
    );
  }

  test('a contact talking with no current target selects and joins them', () async {
    await build();
    container.read(incomingCallProvider);
    await Future<void>.delayed(Duration.zero);

    deliverTalking(theirPk);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final selection = container.read(currentTargetProvider);
    expect(selection?.target.id, theirPk);
    expect(selection?.target.name, 'ZULU-1');
    expect(host.switchTargetCalls, hasLength(1));
    expect(host.switchTargetCalls.single.id, theirPk);
    final expectedRoom = await deriveDirectRoom(
      myKeyPair: myKeyPair,
      theirEdwardsPublicKey: theirKeyPair.publicKey,
    );
    expect(host.switchTargetCalls.single.roomId, expectedRoom);
  });

  test('an active TX is never stolen by an incoming talking event', () async {
    await build();
    container.read(incomingCallProvider);
    final radio = container.read(radioStateProvider.notifier) as _TestRadioStateController;
    // Select a different (already-current) target and start TX on it.
    container.read(currentTargetProvider.notifier).state = TalkTargetSelection(
      const TalkTarget(kind: TalkTargetKind.contact, id: 'someone-else', name: 'X-RAY', roomId: 'ROOM1'),
    );
    radio.setState(const RadioState(phase: RadioPhase.tx));
    await Future<void>.delayed(Duration.zero);

    deliverTalking(theirPk);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(host.switchTargetCalls, isEmpty);
    expect(container.read(currentTargetProvider)?.target.id, 'someone-else');
  });

  test('a deliberately selected different target is not overridden while '
      'not idle', () async {
    await build();
    container.read(incomingCallProvider);
    final radio = container.read(radioStateProvider.notifier) as _TestRadioStateController;
    container.read(currentTargetProvider.notifier).state = TalkTargetSelection(
      const TalkTarget(kind: TalkTargetKind.contact, id: 'someone-else', name: 'X-RAY', roomId: 'ROOM1'),
    );
    radio.setState(const RadioState(phase: RadioPhase.rxActive));
    await Future<void>.delayed(Duration.zero);

    deliverTalking(theirPk);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(host.switchTargetCalls, isEmpty);
    expect(container.read(currentTargetProvider)?.target.id, 'someone-else');
  });

  test('talking:false never triggers a join', () async {
    await build();
    container.read(incomingCallProvider);
    await Future<void>.delayed(Duration.zero);

    deliverTalking(theirPk, talking: false);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(host.switchTargetCalls, isEmpty);
    expect(container.read(currentTargetProvider), isNull);
  });

  test('a talking pk that is not a known contact is ignored', () async {
    await build(contacts: const []);
    container.read(incomingCallProvider);
    await Future<void>.delayed(Duration.zero);

    deliverTalking(theirPk);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(host.switchTargetCalls, isEmpty);
    expect(container.read(currentTargetProvider), isNull);
  });

  test('an idle current target is still overridden by an incoming talking '
      'contact', () async {
    await build();
    container.read(incomingCallProvider);
    final radio = container.read(radioStateProvider.notifier) as _TestRadioStateController;
    container.read(currentTargetProvider.notifier).state = TalkTargetSelection(
      const TalkTarget(kind: TalkTargetKind.contact, id: 'someone-else', name: 'X-RAY', roomId: 'ROOM1'),
    );
    radio.setState(const RadioState(phase: RadioPhase.idle));
    await Future<void>.delayed(Duration.zero);

    deliverTalking(theirPk);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(host.switchTargetCalls, hasLength(1));
    expect(container.read(currentTargetProvider)?.target.id, theirPk);
  });
}
