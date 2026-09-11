/// Local persistence for group memberships (Technical §6.1 — same
/// `shared_preferences` JSON convention as `lib/core/contacts/**`, for the
/// same reason: `sqflite` is not in the frozen `pubspec.yaml`).
///
/// The opened group secret is stored as base64 — plaintext-at-rest on the
/// same device that already holds the private key able to open it from
/// the sealed copy again; storing the opened form just avoids re-opening
/// on every launch.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'group_models.dart';

abstract class GroupsRepository {
  Future<List<GroupMembership>> loadGroups();
  Future<void> saveGroups(List<GroupMembership> groups);
}

class SharedPreferencesGroupsRepository implements GroupsRepository {
  SharedPreferencesGroupsRepository(this._prefs);

  static const _groupsKey = 'keryx.v2.groups';

  final SharedPreferences _prefs;

  @override
  Future<List<GroupMembership>> loadGroups() async {
    final raw = _prefs.getString(_groupsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, Object?>>().map(_fromJson).toList();
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> saveGroups(List<GroupMembership> groups) async {
    await _prefs.setString(_groupsKey, jsonEncode(groups.map(_toJson).toList()));
  }

  Map<String, Object?> _toJson(GroupMembership g) => {
    'id': g.id,
    'name': g.name,
    'role': g.role,
    'key_version': g.keyVersion,
    'secret': base64Encode(g.secret),
    'room_id': g.roomId,
  };

  GroupMembership _fromJson(Map<String, Object?> json) => GroupMembership(
    id: json['id'] as String,
    name: json['name'] as String,
    role: json['role'] as String,
    keyVersion: json['key_version'] as int,
    secret: base64Decode(json['secret'] as String),
    roomId: json['room_id'] as String,
  );
}
