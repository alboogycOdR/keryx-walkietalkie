/// Signed REST client for the v2 directory contract
/// (`token-svc/openapi-v2.yaml`, Technical §4.2). Mirrors
/// `lib/services/linked/token_client.dart`'s `dart:io`-`HttpClient`
/// convention (no network package dependency; `pubspec.yaml` is outside
/// this task's `Owned_Paths`) and TASK-083's signing helper via
/// [signedDirectoryHeaders].
///
/// No storage, no UI, no session wiring — this is the pure wire layer.
/// `lib/core/contacts/**`/`lib/core/groups/**` own persistence and the
/// presence-merged view.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:keryx/core/identity/keys.dart' show IdentityKeyPair;

import 'directory_errors.dart';
import 'directory_models.dart';
import 'directory_signing.dart';

const _logName = 'keryx.directory';

class DirectoryClient {
  DirectoryClient({
    required Uri baseUrl,
    required IdentityKeyPair keyPair,
    HttpClient? client,
    Duration? requestTimeout,
  }) : _baseUrl = baseUrl,
       _keyPair = keyPair,
       _client = client ?? HttpClient(),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 10);

  final Uri _baseUrl;
  final IdentityKeyPair _keyPair;
  final HttpClient _client;
  final Duration _requestTimeout;

  void close() => _client.close(force: true);

  // ---- identity ----------------------------------------------------

  Future<IdentityRegistration> registerIdentity(String callsign) async {
    final json = await _send('POST', '/v2/identity', {'callsign': callsign});
    return IdentityRegistration.fromJson(json);
  }

  Future<DirectoryMe> getMe() async {
    final json = await _send('GET', '/v2/identity/me', null);
    return DirectoryMe.fromJson(json);
  }

  Future<void> patchCallsign(String callsign) =>
      _send('PATCH', '/v2/identity/callsign', {'callsign': callsign});

  // ---- contacts ------------------------------------------------------

  Future<void> sendContactRequest(String toPk) =>
      _send('POST', '/v2/contacts/requests', {'to_pk': toPk});

  Future<void> acceptContactRequest(String fromPk) =>
      _send('POST', '/v2/contacts/requests/$fromPk:accept', const {});

  Future<void> declineContactRequest(String fromPk) =>
      _send('POST', '/v2/contacts/requests/$fromPk:decline', const {});

  Future<void> blockContactRequest(String fromPk) =>
      _send('POST', '/v2/contacts/requests/$fromPk:block', const {});

  Future<void> removeContact(String pk) => _send('DELETE', '/v2/contacts/$pk', null);

  // ---- groups ---------------------------------------------------------

  Future<DirectoryGroupCreated> createGroup({
    required String name,
    required String mySecretEnc,
    required String roomId,
  }) async {
    final json = await _send('POST', '/v2/groups', {
      'name': name,
      'my_secret_enc': mySecretEnc,
      'room_id': roomId,
    });
    return DirectoryGroupCreated.fromJson(json);
  }

  Future<void> joinGroup({required String token, required String mySecretEnc}) =>
      _send('POST', '/v2/groups/join', {'token': token, 'my_secret_enc': mySecretEnc});

  Future<DirectoryGroupDetail> getGroup(String id) async {
    final json = await _send('GET', '/v2/groups/$id', null);
    return DirectoryGroupDetail.fromJson(json);
  }

  Future<void> renameGroup(String id, String name) =>
      _send('PATCH', '/v2/groups/$id', {'name': name});

  Future<DirectoryInvite> mintInvite(String id, {Object? expiresIn}) async {
    final json = await _send(
      'POST',
      '/v2/groups/$id/invites',
      expiresIn == null ? const {} : {'expires_in': expiresIn},
    );
    return DirectoryInvite.fromJson(json);
  }

  Future<void> rotateGroup({
    required String id,
    required Map<String, String> secretsEnc,
    required String roomId,
  }) => _send('POST', '/v2/groups/$id/rotate', {'secrets_enc': secretsEnc, 'room_id': roomId});

  Future<void> leaveGroup(String id) => _send('DELETE', '/v2/groups/$id/members/me', null);

  Future<void> removeMember({
    required String id,
    required String pk,
    required Map<String, String> secretsEnc,
    required String roomId,
  }) => _send('DELETE', '/v2/groups/$id/members/$pk', {
    'secrets_enc': secretsEnc,
    'room_id': roomId,
  });

  Future<void> makeAdmin({required String id, required String pk}) =>
      _send('POST', '/v2/groups/$id/members/$pk:admin', const {});

  // ---- alerts ----------------------------------------------------------

  Future<void> sendAlert(String toPk) => _send('POST', '/v2/alerts', {'to_pk': toPk});

  // ---- transport ---------------------------------------------------

  /// Every path this client calls, in call order — read by
  /// `test/services/directory/openapi_contract_test.dart` to prove each one
  /// exists in `openapi-v2.yaml` (this task's contract-test criterion).
  /// Path params are represented with their OpenAPI placeholder names so the
  /// comparison is purely structural, matching the spec's own `{from_pk}`
  /// style (including the `:action` suffix on the same segment).
  static const calledPaths = <String>[
    '/v2/identity',
    '/v2/identity/me',
    '/v2/identity/callsign',
    '/v2/contacts/requests',
    '/v2/contacts/requests/{from_pk}:accept',
    '/v2/contacts/requests/{from_pk}:decline',
    '/v2/contacts/requests/{from_pk}:block',
    '/v2/contacts/{pk}',
    '/v2/groups',
    '/v2/groups/join',
    '/v2/groups/{id}',
    '/v2/groups/{id}/invites',
    '/v2/groups/{id}/rotate',
    '/v2/groups/{id}/members/me',
    '/v2/groups/{id}/members/{pk}',
    '/v2/groups/{id}/members/{pk}:admin',
    '/v2/alerts',
  ];

  Future<Map<String, Object?>> _send(String method, String path, Object? body) async {
    final uri = _baseUrl.resolve(path.startsWith('/') ? path.substring(1) : path);
    final bodyJson = body == null ? '' : jsonEncode(body);

    late final HttpClientRequest request;
    late final HttpClientResponse response;
    try {
      request = await _client.openUrl(method, uri).timeout(_requestTimeout);
      final headers = await signedDirectoryHeaders(
        keyPair: _keyPair,
        method: method,
        path: uri.path,
        body: bodyJson,
      );
      for (final entry in headers.entries) {
        request.headers.set(entry.key, entry.value);
      }
      if (body != null) {
        request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        request.add(utf8.encode(bodyJson));
      }
      response = await request.close().timeout(_requestTimeout);
    } on TimeoutException catch (error, stack) {
      developer.log('directory request timed out', name: _logName, error: error, stackTrace: stack);
      throw DirectoryException.transport('directory request timed out: $error');
    } on Object catch (error, stack) {
      developer.log('directory request transport failure', name: _logName, error: error, stackTrace: stack);
      throw DirectoryException.transport('failed to reach directory: $error');
    }

    final String rawBody;
    try {
      rawBody = await response.transform(utf8.decoder).join().timeout(_requestTimeout);
    } on TimeoutException catch (error, stack) {
      developer.log('directory response body timed out', name: _logName, error: error, stackTrace: stack);
      throw DirectoryException.transport('directory response body timed out: $error');
    }

    Map<String, Object?> decoded = const {};
    if (rawBody.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawBody);
        if (parsed is Map<String, Object?>) decoded = parsed;
      } on FormatException {
        // fall through — empty/non-JSON body on a 2xx (e.g. plain 200 OK)
        // is not itself an error; only surfaced if the caller needed a field.
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = decoded['error'] as String?;
      developer.log(
        'directory request refused: status=${response.statusCode} code=$code',
        name: _logName,
      );
      throw DirectoryException.fromResponse(response.statusCode, code);
    }

    return decoded;
  }
}
