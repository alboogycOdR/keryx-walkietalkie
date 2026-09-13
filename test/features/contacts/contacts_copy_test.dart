import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/services/directory/directory.dart';

/// `ContactsCopy.requestRefused` — one honest line per `token-svc`
/// contact-request refusal (`directory.py:send_request`), so a field
/// report can tell "they aren't registered" from "you're already contacts"
/// without a diagnostic build.
void main() {
  DirectoryException refusal(int status, String code) =>
      DirectoryException.fromResponse(status, code);

  test('every send_request refusal code maps to a distinct, specific line', () {
    final codes = <String, int>{
      'not_found': 404,
      'unknown_identity': 401,
      'self_request': 422,
      'already_contacts': 409,
      'already_pending': 409,
      'too_many_outstanding': 429,
    };
    final lines = <String>{};
    for (final entry in codes.entries) {
      final line = ContactsCopy.requestRefused(refusal(entry.value, entry.key));
      expect(line, isNot(ContactsCopy.requestFailed),
          reason: '${entry.key} must not collapse into the generic sentence');
      expect(line, isNot(contains(entry.key)),
          reason: '${entry.key} must be user language, not a raw wire code');
      lines.add(line);
    }
    expect(lines, hasLength(codes.length), reason: 'no two codes may share a line');
  });

  test('not_found names the other party (they are not registered yet)', () {
    expect(
      ContactsCopy.requestRefused(refusal(404, 'not_found')),
      contains("haven't registered"),
    );
  });

  test('unknown_identity names this phone (it is not registered yet)', () {
    expect(
      ContactsCopy.requestRefused(refusal(401, 'unknown_identity')),
      contains("This phone isn't registered"),
    );
  });

  test('blocked does not disclose the block', () {
    expect(
      ContactsCopy.requestRefused(refusal(403, 'blocked')),
      ContactsCopy.requestFailed,
    );
  });

  test('a transport failure is the plain generic sentence', () {
    expect(
      ContactsCopy.requestRefused(DirectoryException.transport('unreachable')),
      ContactsCopy.requestFailed,
    );
  });

  test('an unrecognised server code keeps the generic sentence but appends '
      'the raw code so it can be reported', () {
    expect(
      ContactsCopy.requestRefused(refusal(418, 'teapot_mode')),
      '${ContactsCopy.requestFailed} (teapot_mode)',
    );
  });
}
