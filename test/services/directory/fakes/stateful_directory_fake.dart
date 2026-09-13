import 'dart:convert';
import 'dart:typed_data';

import 'package:keryx/features/my_code/keryx_id_link.dart'
    show decodeUnpaddedBase64Url, encodeUnpaddedBase64Url;

import 'fake_directory_server.dart';

/// Loopback stand-in for `token-svc`'s identity/contacts/`POST /token`
/// state machine (Technical §4.2, §5.4; `token-svc/app/directory.py`,
/// `groups.py:ensure_direct_room`/`assert_room_member`, `main.py:153-182`).
///
/// Plugged in as [FakeDirectoryServer.responder]. The server's default
/// (stateless `200 {}`) is unchanged — existing tests that never set a
/// responder keep their previous behaviour.
class StatefulDirectoryFake {
  StatefulDirectoryFake({int Function()? nowUnixSeconds})
    : _now = nowUnixSeconds ??
          (() => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000);

  final int Function() _now;

  /// Canonical unpadded-base64url pk → callsign.
  final Map<String, String> identities = {};

  /// `"fromPk|toPk"` → pending request.
  final Map<String, _PendingRequest> _pending = {};

  /// Ordered-pair key `"loPk|hiPk"` of accepted contacts.
  final Set<String> contacts = {};

  /// Ordered-pair key → 16-char RFC 4648 room id.
  final Map<String, String> directRooms = {};

  static final _callsignRe = RegExp(r'^[A-Za-z0-9-]{2,12}$');
  static final _roomIdRe = RegExp(r'^[A-Z2-7]{16}$');
  static const _requestTtlSeconds = 7 * 24 * 3600;
  static const _maxOutstanding = 20;

  DirectoryFakeResponse call(RecordedDirectoryRequest request) =>
      respond(request);

  DirectoryFakeResponse respond(RecordedDirectoryRequest request) {
    final caller = _decodeCaller(request.callerKeyHeader);
    if (caller == null) {
      return _error(401, 'missing_signature');
    }

    final method = request.method.toUpperCase();
    final path = request.path;

    if (method == 'POST' && path == '/v2/identity') {
      return _postIdentity(caller, request.bodyJson);
    }
    if (method == 'PATCH' && path == '/v2/identity/callsign') {
      return _patchCallsign(caller, request.bodyJson);
    }
    if (method == 'GET' && path == '/v2/identity/me') {
      return _getMe(caller);
    }
    if (method == 'POST' && path == '/v2/contacts/requests') {
      return _sendRequest(caller, request.bodyJson);
    }
    final accept = _matchSuffix(path, '/v2/contacts/requests/', ':accept');
    if (method == 'POST' && accept != null) {
      return _accept(caller, accept);
    }
    if (method == 'POST' && path == '/token') {
      return _mintToken(caller, request.bodyJson);
    }
    return const DirectoryFakeResponse(statusCode: 200, body: {});
  }

  /// Test seam: mark [aPk] and [bPk] as contacts without walking HTTP.
  void seedContact(String aPk, String bPk) {
    contacts.add(_pairKey(aPk, bPk));
  }

  bool hasDirectRoom(String roomId) => directRooms.containsValue(roomId);

  String? directRoomFor(String aPk, String bPk) =>
      directRooms[_pairKey(aPk, bPk)];

  DirectoryFakeResponse _postIdentity(
    String caller,
    Map<String, Object?>? body,
  ) {
    final callsign = body?['callsign'];
    if (callsign is! String || !_callsignRe.hasMatch(callsign)) {
      return _error(422, 'invalid_callsign');
    }
    final existing = identities[caller];
    if (existing != null) {
      if (existing != callsign) return _error(409, 'identity_exists');
      return DirectoryFakeResponse(
        statusCode: 200,
        body: {'pk': caller, 'callsign': callsign},
      );
    }
    if (identities.containsValue(callsign)) {
      return _error(409, 'callsign_taken');
    }
    identities[caller] = callsign;
    return DirectoryFakeResponse(
      statusCode: 200,
      body: {'pk': caller, 'callsign': callsign},
    );
  }

  DirectoryFakeResponse _patchCallsign(
    String caller,
    Map<String, Object?>? body,
  ) {
    if (!identities.containsKey(caller)) {
      return _error(401, 'unknown_identity');
    }
    final callsign = body?['callsign'];
    if (callsign is! String || !_callsignRe.hasMatch(callsign)) {
      return _error(422, 'invalid_callsign');
    }
    if (identities[caller] == callsign) {
      return DirectoryFakeResponse(
        statusCode: 200,
        body: {'callsign': callsign},
      );
    }
    final takenBy = identities.entries
        .where((e) => e.value == callsign && e.key != caller)
        .map((e) => e.key)
        .firstOrNull;
    if (takenBy != null) return _error(409, 'callsign_taken');
    identities[caller] = callsign;
    return DirectoryFakeResponse(
      statusCode: 200,
      body: {'callsign': callsign},
    );
  }

  DirectoryFakeResponse _getMe(String caller) {
    final callsign = identities[caller];
    if (callsign == null) return _error(401, 'unknown_identity');
    final now = _now();
    final contactRows = <Map<String, Object?>>[];
    for (final pair in contacts) {
      final other = _otherOf(pair, caller);
      if (other == null) continue;
      final otherCallsign = identities[other];
      if (otherCallsign == null) continue;
      contactRows.add({
        'pk': other,
        'callsign': otherCallsign,
        'status': 'offline',
        'last_seen_at': now,
      });
    }
    contactRows.sort(
      (a, b) => (a['callsign'] as String).compareTo(b['callsign'] as String),
    );

    final pendingIn = <Map<String, Object?>>[];
    final pendingOut = <Map<String, Object?>>[];
    for (final entry in _pending.entries) {
      final req = entry.value;
      if (req.expiresAt <= now) continue;
      if (req.toPk == caller) {
        pendingIn.add({
          'from_pk': req.fromPk,
          'callsign': identities[req.fromPk] ?? '',
          'created_at': req.createdAt,
          'expires_at': req.expiresAt,
        });
      } else if (req.fromPk == caller) {
        pendingOut.add({
          'to_pk': req.toPk,
          'created_at': req.createdAt,
          'expires_at': req.expiresAt,
        });
      }
    }

    return DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'pk': caller,
        'callsign': callsign,
        'status': 'offline',
        'contacts': contactRows,
        'pending_in': pendingIn,
        'pending_out': pendingOut,
        'groups': <Object?>[],
      },
    );
  }

  DirectoryFakeResponse _sendRequest(
    String caller,
    Map<String, Object?>? body,
  ) {
    if (!identities.containsKey(caller)) {
      return _error(401, 'unknown_identity');
    }
    final toRaw = body?['to_pk'];
    if (toRaw is! String) return _error(422, 'invalid_request');
    final toPk = _canonicalizePk(toRaw);
    if (toPk == null) return _error(422, 'invalid_request');
    if (toPk == caller) return _error(422, 'self_request');
    if (!identities.containsKey(toPk)) return _error(404, 'not_found');
    if (contacts.contains(_pairKey(caller, toPk))) {
      return _error(409, 'already_contacts');
    }
    final key = '$caller|$toPk';
    final now = _now();
    final existing = _pending[key];
    if (existing != null && existing.expiresAt > now) {
      return _error(409, 'already_pending');
    }
    final outstanding = _pending.values
        .where((r) => r.fromPk == caller && r.expiresAt > now)
        .length;
    if (outstanding >= _maxOutstanding) {
      return _error(429, 'too_many_outstanding');
    }
    final expiresAt = now + _requestTtlSeconds;
    _pending[key] = _PendingRequest(
      fromPk: caller,
      toPk: toPk,
      createdAt: now,
      expiresAt: expiresAt,
    );
    return DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'to_pk': toPk,
        'expires_at': expiresAt,
        'state': 'pending',
      },
    );
  }

  DirectoryFakeResponse _accept(String caller, String fromRaw) {
    if (!identities.containsKey(caller)) {
      return _error(401, 'unknown_identity');
    }
    final fromPk = _canonicalizePk(fromRaw);
    if (fromPk == null) return _error(400, 'invalid_request');
    final key = '$fromPk|$caller';
    final req = _pending[key];
    final now = _now();
    if (req == null) return _error(404, 'request_not_found');
    if (req.expiresAt <= now) {
      _pending.remove(key);
      return _error(410, 'request_expired');
    }
    _pending.remove(key);
    contacts.add(_pairKey(caller, fromPk));
    return const DirectoryFakeResponse(
      statusCode: 200,
      body: {'state': 'accepted'},
    );
  }

  /// Real order (`token-svc/app/main.py:174-180`):
  /// `unknown_identity` → `ensure_direct_room(peer_pk)` → `assert_room_member`.
  DirectoryFakeResponse _mintToken(
    String caller,
    Map<String, Object?>? body,
  ) {
    if (!identities.containsKey(caller)) {
      return _error(401, 'unknown_identity');
    }
    final roomIdRaw = body?['room_id'];
    if (roomIdRaw is! String) return _error(422, 'invalid_request');
    final roomId = roomIdRaw.trim().toUpperCase();
    if (!_roomIdRe.hasMatch(roomId)) return _error(422, 'invalid_request');

    final peerRaw = body?['peer_pk'];
    if (peerRaw is String && peerRaw.isNotEmpty) {
      final peer = _canonicalizePk(peerRaw);
      if (peer == null) return _error(401, 'invalid_key');
      if (peer == caller) return _error(422, 'invalid_request');
      if (!contacts.contains(_pairKey(caller, peer))) {
        return _error(403, 'not_contacts');
      }
      final pair = _pairKey(caller, peer);
      final existing = directRooms[pair];
      if (existing != null) {
        if (existing != roomId) return _error(409, 'room_conflict');
      } else {
        final takenBy = directRooms.entries
            .where((e) => e.value == roomId)
            .map((e) => e.key)
            .firstOrNull;
        if (takenBy != null && takenBy != pair) {
          return _error(409, 'room_conflict');
        }
        directRooms[pair] = roomId;
      }
    }

    final memberOfDirect = directRooms.entries.any(
      (e) => e.value == roomId && _otherOf(e.key, caller) != null,
    );
    if (!memberOfDirect) {
      return _error(403, 'not_member');
    }

    final callsign = identities[caller]!;
    return DirectoryFakeResponse(
      statusCode: 200,
      body: {
        'token': 'journey-jwt-$roomId',
        'identity': '$callsign#deadbeef',
        'ttl_seconds': 60,
      },
    );
  }

  static DirectoryFakeResponse _error(int status, String code) =>
      DirectoryFakeResponse(statusCode: status, body: {'error': code});

  static String? _matchSuffix(String path, String prefix, String suffix) {
    if (!path.startsWith(prefix) || !path.endsWith(suffix)) return null;
    final inner = path.substring(prefix.length, path.length - suffix.length);
    return inner.isEmpty ? null : inner;
  }

  static String _pairKey(String a, String b) {
    final aBytes = _mustDecode(a);
    final bBytes = _mustDecode(b);
    final ordered = _bytesLess(aBytes, bBytes) ? [a, b] : [b, a];
    return '${ordered[0]}|${ordered[1]}';
  }

  static String? _otherOf(String pairKey, String me) {
    final parts = pairKey.split('|');
    if (parts.length != 2) return null;
    if (parts[0] == me) return parts[1];
    if (parts[1] == me) return parts[0];
    return null;
  }

  static bool _bytesLess(Uint8List a, Uint8List b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return a.length < b.length;
  }

  static String? _decodeCaller(String? header) {
    if (header == null || header.isEmpty) return null;
    return _canonicalizePk(header);
  }

  static String? _canonicalizePk(String raw) {
    final bytes = _decodePk(raw);
    if (bytes == null || bytes.length != 32) return null;
    return encodeUnpaddedBase64Url(bytes);
  }

  static Uint8List _mustDecode(String pk) {
    final bytes = _decodePk(pk);
    if (bytes == null) {
      throw FormatException('expected 32-byte pk, got $pk');
    }
    return bytes;
  }

  /// Accepts unpadded base64url (DirectoryClient) and standard base64
  /// (TokenClient's `signRequest`).
  static Uint8List? _decodePk(String raw) {
    try {
      final urlSafe = raw.replaceAll('+', '-').replaceAll('/', '_');
      final bytes = decodeUnpaddedBase64Url(urlSafe);
      if (bytes.length == 32) return bytes;
    } on FormatException {
      // fall through
    }
    try {
      final bytes = Uint8List.fromList(base64.decode(raw));
      if (bytes.length == 32) return bytes;
    } on FormatException {
      return null;
    }
    return null;
  }
}

class _PendingRequest {
  const _PendingRequest({
    required this.fromPk,
    required this.toPk,
    required this.createdAt,
    required this.expiresAt,
  });

  final String fromPk;
  final String toPk;
  final int createdAt;
  final int expiresAt;
}
