/// Group store, sealed-secret handling, rotation (Technical §5, §6.1; PRD
/// V2-FR-020..025). Owns the persisted, opened-secret view; the wire layer
/// (`lib/services/directory/**`) and the sealed-box/room-derivation
/// primitives (`lib/core/identity/**`, TASK-083; `lib/core/rooms/**`,
/// TASK-087) are used, not owned, by this file.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair;
import 'package:keryx/core/identity/sealed_box.dart' show openSealed, sealToPublicKey;
import 'package:keryx/core/rooms/rooms.dart' show deriveGroupRoom;
import 'package:keryx/services/directory/directory.dart';

import 'group_events.dart';
import 'group_models.dart';
import 'groups_repository.dart';

class GroupsController {
  GroupsController({
    required DirectoryClient directoryClient,
    required GroupsRepository repository,
    required IdentityKeyPair keyPair,
    PresenceClient? presenceClient,
    Random? secureRandom,
  }) : _directory = directoryClient,
       _repository = repository,
       _keyPair = keyPair,
       _random = secureRandom ?? Random.secure() {
    if (presenceClient != null) {
      _rotationSub = presenceClient.rotationNotices.listen(_onRotationNotice);
    }
  }

  final DirectoryClient _directory;
  final GroupsRepository _repository;
  final IdentityKeyPair _keyPair;
  final Random _random;
  StreamSubscription<GroupRotationNotice>? _rotationSub;

  final _groupsController = StreamController<List<GroupMembership>>.broadcast(sync: true);
  final _eventsController = StreamController<Object>.broadcast(sync: true); // GroupKeyChanged | GroupMembershipEnded

  List<GroupMembership> _groups = const [];
  bool _loaded = false;

  Stream<List<GroupMembership>> get groups => _groupsController.stream;

  /// [GroupKeyChanged] and [GroupMembershipEnded] events.
  Stream<Object> get events => _eventsController.stream;

  List<GroupMembership> get groupsSnapshot => List.unmodifiable(_groups);

  Future<void> loadFromDisk() async {
    _groups = await _repository.loadGroups();
    _loaded = true;
    _emitGroups();
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) await loadFromDisk();
  }

  /// Mints a fresh 32-byte group secret, creates the group server-side
  /// (sealed to this identity's own key so the creator's own copy round-
  /// trips through the same open path every other member uses), and
  /// adopts it locally as `key_version` 1, admin.
  Future<GroupMembership> createGroup(String name) async {
    await _ensureLoaded();
    final secret = _randomSecret();
    final roomId = deriveGroupRoom(secret);
    final mySealed = await sealToPublicKey(secret, _keyPair.publicKey);
    final created = await _directory.createGroup(
      name: name,
      mySecretEnc: base64Encode(mySealed),
      roomId: roomId,
    );
    final membership = GroupMembership(
      id: created.id,
      name: name,
      role: 'admin',
      keyVersion: 1,
      secret: secret,
      roomId: roomId,
    );
    _upsert(membership);
    await _persist();
    return membership;
  }

  /// Joins via an invite token + the group secret carried in the invite
  /// link (Technical §5.2 — the secret rides in the link, not the server).
  /// [groupId] is the id the invite link/QR also carries (`?g=<groupId>`).
  Future<GroupMembership> joinGroup({
    required String groupId,
    required String groupName,
    required String token,
    required List<int> secret,
  }) async {
    await _ensureLoaded();
    final roomId = deriveGroupRoom(secret);
    final mySealed = await sealToPublicKey(secret, _keyPair.publicKey);
    await _directory.joinGroup(token: token, mySecretEnc: base64Encode(mySealed));
    final membership = GroupMembership(
      id: groupId,
      name: groupName,
      role: 'member',
      keyVersion: 1,
      secret: secret,
      roomId: roomId,
    );
    _upsert(membership);
    await _persist();
    return membership;
  }

  /// Pulls `GET /v2/identity/me` and reconciles: every group the server
  /// still lists gets its sealed copy opened and adopted if the
  /// `key_version` advanced (emits [GroupKeyChanged]); any local group the
  /// server no longer lists is dropped (emits [GroupMembershipEnded] —
  /// this is how a removed member's store notices removal, Technical §5.3).
  Future<void> refreshFromServer() async {
    await _ensureLoaded();
    final me = await _directory.getMe();
    final serverIds = me.groups.map((g) => g.id).toSet();
    for (final ended in _groups.where((g) => !serverIds.contains(g.id))) {
      _eventsController.add(GroupMembershipEnded(groupId: ended.id));
    }
    _groups = _groups.where((g) => serverIds.contains(g.id)).toList();

    for (final serverGroup in me.groups) {
      final existing = _groups.firstWhere(
        (g) => g.id == serverGroup.id,
        orElse: () => GroupMembership(
          id: serverGroup.id,
          name: serverGroup.name,
          role: serverGroup.role,
          keyVersion: -1,
          secret: const [],
          roomId: '',
        ),
      );
      if (existing.keyVersion == serverGroup.keyVersion && existing.secret.isNotEmpty) {
        // Unchanged key; just refresh name/role in case they changed.
        _upsert(existing.copyWith(name: serverGroup.name, role: serverGroup.role));
        continue;
      }
      final secret = await openSealed(base64Decode(serverGroup.secretEnc), _keyPair);
      final roomId = deriveGroupRoom(secret);
      final updated = GroupMembership(
        id: serverGroup.id,
        name: serverGroup.name,
        role: serverGroup.role,
        keyVersion: serverGroup.keyVersion,
        secret: secret,
        roomId: roomId,
      );
      _upsert(updated);
      if (existing.keyVersion != -1) {
        _eventsController.add(
          GroupKeyChanged(groupId: updated.id, keyVersion: updated.keyVersion, newRoomId: roomId),
        );
      }
    }
    await _persist();
  }

  /// Admin action: mints a new secret, seals it to every remaining member
  /// (caller supplies [secretsEncByPk], one sealed copy per remaining
  /// member — including this admin's own, so the two calls this method
  /// wraps produce a self-consistent membership set), posts the rotation,
  /// and adopts the new secret locally immediately (no need to wait for
  /// the presence-WS notice for the admin who just made the change).
  Future<void> rotate({
    required String groupId,
    required List<int> newSecret,
    required Map<String, String> secretsEncByPk,
  }) async {
    await _ensureLoaded();
    final roomId = deriveGroupRoom(newSecret);
    await _directory.rotateGroup(id: groupId, secretsEnc: secretsEncByPk, roomId: roomId);
    _adoptRotated(groupId, newSecret, roomId);
  }

  /// Admin action: removes [pk] and rotates in the same call (the
  /// contract requires `secrets_enc` to be exactly the remaining members).
  Future<void> removeMember({
    required String groupId,
    required String pk,
    required List<int> newSecret,
    required Map<String, String> secretsEncByPk,
  }) async {
    await _ensureLoaded();
    final roomId = deriveGroupRoom(newSecret);
    await _directory.removeMember(id: groupId, pk: pk, secretsEnc: secretsEncByPk, roomId: roomId);
    _adoptRotated(groupId, newSecret, roomId);
  }

  Future<void> makeAdmin({required String groupId, required String pk}) =>
      _directory.makeAdmin(id: groupId, pk: pk);

  Future<void> rename(String groupId, String name) async {
    await _ensureLoaded();
    await _directory.renameGroup(groupId, name);
    final existing = _groups.where((g) => g.id == groupId);
    if (existing.isNotEmpty) {
      _upsert(existing.first.copyWith(name: name));
      await _persist();
    }
  }

  Future<DirectoryInvite> mintInvite(String groupId, {Object? expiresIn}) =>
      _directory.mintInvite(groupId, expiresIn: expiresIn);

  Future<void> leave(String groupId) async {
    await _ensureLoaded();
    await _directory.leaveGroup(groupId);
    _groups = _groups.where((g) => g.id != groupId).toList();
    await _persist();
    _eventsController.add(GroupMembershipEnded(groupId: groupId));
  }

  void _onRotationNotice(GroupRotationNotice notice) {
    // The notice only says a rotation happened; the sealed copy still has
    // to be fetched (Technical §5.3: "Members ... fetch their sealed
    // copy"). A full resync is the simplest correct way to do that with
    // the endpoints this contract exposes (no per-group "my sealed copy"
    // endpoint outside of `GET /v2/identity/me`).
    unawaited(refreshFromServer());
  }

  void _adoptRotated(String groupId, List<int> newSecret, String roomId) {
    final existing = _groups.where((g) => g.id == groupId);
    final base = existing.isNotEmpty ? existing.first : null;
    final nextVersion = (base?.keyVersion ?? 0) + 1;
    final membership = GroupMembership(
      id: groupId,
      name: base?.name ?? '',
      role: base?.role ?? 'admin',
      keyVersion: nextVersion,
      secret: newSecret,
      roomId: roomId,
    );
    _upsert(membership);
    unawaited(_persist());
    _eventsController.add(GroupKeyChanged(groupId: groupId, keyVersion: nextVersion, newRoomId: roomId));
  }

  List<int> _randomSecret() => List<int>.generate(32, (_) => _random.nextInt(256));

  void _upsert(GroupMembership membership) {
    _groups = [..._groups.where((g) => g.id != membership.id), membership];
    _emitGroups();
  }

  Future<void> _persist() async {
    await _repository.saveGroups(_groups);
    _emitGroups();
  }

  void _emitGroups() {
    if (!_groupsController.isClosed) _groupsController.add(List.unmodifiable(_groups));
  }

  Future<void> dispose() async {
    await _rotationSub?.cancel();
    await _groupsController.close();
    await _eventsController.close();
  }
}
