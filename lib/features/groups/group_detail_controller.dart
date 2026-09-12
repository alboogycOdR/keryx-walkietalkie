/// Drives the group detail screen: member list with presence/admin marks,
/// invite minting, admin actions (rename, remove member, rotate key, make
/// admin), leave (with last-admin promotion), and toast events (Design
/// §2.3, §4; PRD V2-FR-020..025).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:keryx/core/groups/group_events.dart';
import 'package:keryx/core/groups/group_models.dart' show GroupMembership;
import 'package:keryx/core/groups/groups_controller.dart';
import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair;
import 'package:keryx/core/identity/sealed_box.dart' show sealToPublicKey;
import 'package:keryx/services/directory/directory_client.dart';
import 'package:keryx/services/directory/directory_errors.dart';
import 'package:keryx/services/directory/directory_models.dart';

import 'group_view_models.dart';
import 'groups_copy.dart';

/// A toast/snackbar the detail screen should surface, decoupled from any
/// `BuildContext` so the controller stays widget-free and testable
/// (Design §4: "Key rotated" / "Removed from group").
class GroupDetailToast {
  const GroupDetailToast(this.message);
  final String message;
}

/// Immutable snapshot the detail screen renders.
class GroupDetailState {
  const GroupDetailState({
    required this.groupId,
    required this.name,
    required this.members,
    required this.isAdmin,
    required this.isLastAdmin,
    required this.loading,
    this.error,
  });

  const GroupDetailState.loading(this.groupId)
    : name = '',
      members = const [],
      isAdmin = false,
      isLastAdmin = false,
      loading = true,
      error = null;

  final String groupId;
  final String name;
  final List<MemberRow> members;
  final bool isAdmin;
  final bool isLastAdmin;
  final bool loading;
  final String? error;

  GroupDetailState copyWith({
    String? name,
    List<MemberRow>? members,
    bool? isAdmin,
    bool? isLastAdmin,
    bool? loading,
    String? error,
    bool clearError = false,
  }) => GroupDetailState(
    groupId: groupId,
    name: name ?? this.name,
    members: members ?? this.members,
    isAdmin: isAdmin ?? this.isAdmin,
    isLastAdmin: isLastAdmin ?? this.isLastAdmin,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
  );
}

class GroupDetailController {
  GroupDetailController({
    required String groupId,
    required GroupsController groupsController,
    required DirectoryClient directoryClient,
    // Accepted for construction-site symmetry with `GroupsController` (and
    // in case a future contract change needs this identity's own keypair
    // for detail-screen work) even though nothing in this class currently
    // reads it — every seal target's public key already comes from the
    // server's member list (`DirectoryGroupMember.pk`), not from this
    // identity's own pair.
    required IdentityKeyPair keyPair,
    required String myPk,
  }) : _groupId = groupId,
       _groups = groupsController,
       _directory = directoryClient,
       _myPk = myPk,
       _state = GroupDetailState.loading(groupId) {
    _eventsSub = _groups.events.listen(_onGroupEvent);
  }

  final String _groupId;
  final GroupsController _groups;
  final DirectoryClient _directory;
  final String _myPk;
  final Random _random = Random.secure();
  StreamSubscription<Object>? _eventsSub;
  List<DirectoryGroupMember> _rawMembers = const [];

  GroupDetailState _state;
  final _stateController = StreamController<GroupDetailState>.broadcast();
  final _toastController = StreamController<GroupDetailToast>.broadcast();

  GroupDetailState get state => _state;
  Stream<GroupDetailState> get states => _stateController.stream;
  Stream<GroupDetailToast> get toasts => _toastController.stream;

  void _emit(GroupDetailState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  Future<void> load() async {
    try {
      final detail = await _directory.getGroup(_groupId);
      _rawMembers = detail.members;
      _emit(
        _state.copyWith(
          name: detail.name,
          members: buildMemberRows(detail.members, myPk: _myPk),
          isAdmin: detail.members.any((m) => m.pk == _myPk && m.role == 'admin'),
          isLastAdmin: isLastAdmin(detail.members, _myPk),
          loading: false,
          clearError: true,
        ),
      );
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(loading: false, error: _messageFor(e)));
    }
  }

  Future<DirectoryInvite?> mintInvite({Object? expiresIn}) async {
    try {
      return await _directory.mintInvite(_groupId, expiresIn: expiresIn);
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(error: _messageFor(e)));
      return null;
    }
  }

  Future<bool> rename(String name) async {
    try {
      await _groups.rename(_groupId, name);
      _emit(_state.copyWith(name: name, clearError: true));
      return true;
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(error: _messageFor(e)));
      return false;
    }
  }

  Future<bool> makeAdmin(String pk) async {
    try {
      await _groups.makeAdmin(groupId: _groupId, pk: pk);
      await load();
      return true;
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(error: _messageFor(e)));
      return false;
    }
  }

  /// Removes [pk] and rotates the group key to every remaining member in
  /// the same call (contract requirement) — the current membership's
  /// [GroupMembership.secret] is the caller's own opened secret, used to
  /// derive the new room via [GroupsController.removeMember].
  Future<bool> removeMember(String pk) async {
    final remaining = _rawMembers.where((m) => m.pk != pk).toList();
    try {
      final newSecret = await _mintNewSecret();
      final sealed = await _sealToEveryone(newSecret, remaining);
      await _groups.removeMember(
        groupId: _groupId,
        pk: pk,
        newSecret: newSecret,
        secretsEncByPk: sealed,
      );
      await load();
      return true;
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(error: _messageFor(e)));
      return false;
    }
  }

  Future<bool> rotateKey() async {
    try {
      final newSecret = await _mintNewSecret();
      final sealed = await _sealToEveryone(newSecret, _rawMembers);
      await _groups.rotate(groupId: _groupId, newSecret: newSecret, secretsEncByPk: sealed);
      await load();
      return true;
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(error: _messageFor(e)));
      return false;
    }
  }

  /// Leaves the group. If this identity is the sole admin, promotes the
  /// oldest remaining member first (V2-FR-023/024) — a no-op promotion
  /// when nobody else is left (the group simply ends for this device).
  Future<bool> leave() async {
    try {
      if (isLastAdmin(_rawMembers, _myPk)) {
        final promotee = oldestMemberToPromote(_rawMembers, myPk: _myPk);
        if (promotee != null) {
          await _groups.makeAdmin(groupId: _groupId, pk: promotee.pk);
        }
      }
      await _groups.leave(_groupId);
      return true;
    } on DirectoryException catch (e) {
      _emit(_state.copyWith(error: _messageFor(e)));
      return false;
    }
  }

  /// Mints a fresh 32-byte secret via a CSPRNG — the same shape
  /// `GroupsController.createGroup` generates internally, duplicated here
  /// (rather than reached into as private state) because rotation and
  /// removal are this controller's own admin actions.
  Future<List<int>> _mintNewSecret() async =>
      List<int>.generate(32, (_) => _random.nextInt(256));

  Future<Map<String, String>> _sealToEveryone(
    List<int> secret,
    List<DirectoryGroupMember> members,
  ) async {
    final out = <String, String>{};
    for (final member in members) {
      // Members carry only a callsign/role/status/pk today — pk is
      // unpadded base64url (Technical §3.3), the same shape
      // `sealToPublicKey` needs as bytes, so it must be decoded first.
      final pkBytes = base64Url.decode(_padBase64Url(member.pk));
      final sealed = await sealToPublicKey(secret, pkBytes);
      out[member.pk] = base64Encode(sealed);
    }
    return out;
  }

  String _padBase64Url(String value) {
    final remainder = value.length % 4;
    return remainder == 0 ? value : value + ('=' * (4 - remainder));
  }

  void _onGroupEvent(Object event) {
    switch (event) {
      case GroupKeyChanged(:final groupId) when groupId == _groupId:
        _toastController.add(GroupDetailToast(GroupsCopy.keyRotatedToast(_state.name)));
        unawaited(load());
      case GroupMembershipEnded(:final groupId) when groupId == _groupId:
        _toastController.add(GroupDetailToast(GroupsCopy.removedFromGroupToast(_state.name)));
      default:
        break;
    }
  }

  String _messageFor(DirectoryException e) => switch (e.code) {
    DirectoryErrorCode.groupFull => GroupsCopy.groupFullMessage,
    DirectoryErrorCode.notAdmin => 'Only an admin can do that.',
    DirectoryErrorCode.notMember => GroupsCopy.joinFailed,
    _ => GroupsCopy.joinFailed,
  };

  Future<void> dispose() async {
    await _eventsSub?.cancel();
    await _stateController.close();
    await _toastController.close();
  }
}
