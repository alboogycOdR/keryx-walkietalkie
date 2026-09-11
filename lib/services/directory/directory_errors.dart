/// Typed errors for the v2 directory REST contract (Technical §3.3, §4.2;
/// `token-svc/app/errors.py`'s enumerated codes; `token-svc/openapi-v2.yaml`).
///
/// Every non-2xx directory response is `{ "error": "<code>" }`. This file
/// turns that into a typed exception the caller can `switch` on rather than
/// string-compare, while [DirectoryException.code] keeps the raw string for
/// any code the server adds later that this enum hasn't caught up with yet
/// (`DirectoryErrorCode.unknown`).
library;

/// Every code `token-svc/app/errors.py` currently defines, plus [unknown]
/// for forward compatibility with a server that adds a new one.
enum DirectoryErrorCode {
  // Auth (Technical §3.3 / V2-VT-004)
  missingSignature,
  invalidSignature,
  staleTimestamp,
  replayed,
  invalidKey,
  // Identity
  unknownIdentity,
  identityExists,
  callsignTaken,
  invalidCallsign,
  // Contacts (V2-VT-010)
  invalidRequest,
  selfRequest,
  alreadyContacts,
  alreadyPending,
  blocked,
  requestNotFound,
  requestExpired,
  tooManyOutstanding,
  notFound,
  notContacts,
  // Presence
  invalidStatus,
  // Groups / invites / rotation / token / alerts
  notMember,
  notAdmin,
  groupNotFound,
  groupFull,
  alreadyMember,
  invalidName,
  inviteInvalid,
  inviteExpired,
  rotateIncomplete,
  alertRateLimited,
  roomConflict,
  unknown,
}

const Map<String, DirectoryErrorCode> _codesByWire = {
  'missing_signature': DirectoryErrorCode.missingSignature,
  'invalid_signature': DirectoryErrorCode.invalidSignature,
  'stale_timestamp': DirectoryErrorCode.staleTimestamp,
  'replayed': DirectoryErrorCode.replayed,
  'invalid_key': DirectoryErrorCode.invalidKey,
  'unknown_identity': DirectoryErrorCode.unknownIdentity,
  'identity_exists': DirectoryErrorCode.identityExists,
  'callsign_taken': DirectoryErrorCode.callsignTaken,
  'invalid_callsign': DirectoryErrorCode.invalidCallsign,
  'invalid_request': DirectoryErrorCode.invalidRequest,
  'self_request': DirectoryErrorCode.selfRequest,
  'already_contacts': DirectoryErrorCode.alreadyContacts,
  'already_pending': DirectoryErrorCode.alreadyPending,
  'blocked': DirectoryErrorCode.blocked,
  'request_not_found': DirectoryErrorCode.requestNotFound,
  'request_expired': DirectoryErrorCode.requestExpired,
  'too_many_outstanding': DirectoryErrorCode.tooManyOutstanding,
  'not_found': DirectoryErrorCode.notFound,
  'not_contacts': DirectoryErrorCode.notContacts,
  'invalid_status': DirectoryErrorCode.invalidStatus,
  'not_member': DirectoryErrorCode.notMember,
  'not_admin': DirectoryErrorCode.notAdmin,
  'group_not_found': DirectoryErrorCode.groupNotFound,
  'group_full': DirectoryErrorCode.groupFull,
  'already_member': DirectoryErrorCode.alreadyMember,
  'invalid_name': DirectoryErrorCode.invalidName,
  'invite_invalid': DirectoryErrorCode.inviteInvalid,
  'invite_expired': DirectoryErrorCode.inviteExpired,
  'rotate_incomplete': DirectoryErrorCode.rotateIncomplete,
  'alert_rate_limited': DirectoryErrorCode.alertRateLimited,
  'room_conflict': DirectoryErrorCode.roomConflict,
};

/// A non-2xx `{error: code}` response from the directory, or a transport
/// failure that never reached the server ([statusCode] is `null` in that
/// case and [code] is [DirectoryErrorCode.unknown]).
class DirectoryException implements Exception {
  DirectoryException({required this.statusCode, required this.rawCode, this.transportMessage})
    : code = rawCode != null ? (_codesByWire[rawCode] ?? DirectoryErrorCode.unknown) : DirectoryErrorCode.unknown;

  /// Parses a directory error response body (`{"error": "<code>"}`) into a
  /// typed [DirectoryException].
  factory DirectoryException.fromResponse(int statusCode, String? rawCode) =>
      DirectoryException(statusCode: statusCode, rawCode: rawCode);

  /// A transport-level failure (never reached the server, or the response
  /// could not be parsed) — distinct from a real `{error:...}` refusal.
  factory DirectoryException.transport(String message) =>
      DirectoryException(statusCode: null, rawCode: null, transportMessage: message);

  final int? statusCode;
  final String? rawCode;
  final DirectoryErrorCode code;
  final String? transportMessage;

  bool get isTransportFailure => statusCode == null;

  @override
  String toString() => isTransportFailure
      ? 'DirectoryException(transport: $transportMessage)'
      : 'DirectoryException(status: $statusCode, code: $rawCode)';
}
