import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/groups/group_invite_link.dart';

void main() {
  final secret = List<int>.generate(32, (i) => i);

  test('round-trips through encode/decode', () {
    final link = GroupInviteLink(groupId: 'g1', token: 'tok', secret: secret);
    final uri = encodeGroupInviteLink(link);
    expect(uri.scheme, groupInviteLinkScheme);
    expect(uri.host, groupInviteLinkHost);

    final decoded = decodeGroupInviteLink(uri.toString());
    expect(decoded, isA<GroupInviteDecoded>());
    final decodedLink = (decoded as GroupInviteDecoded).link;
    expect(decodedLink.groupId, 'g1');
    expect(decodedLink.token, 'tok');
    expect(decodedLink.secret, secret);
  });

  test('omits exp entirely for no expiry', () {
    final link = GroupInviteLink(groupId: 'g1', token: 'tok', secret: secret);
    final uri = encodeGroupInviteLink(link);
    expect(uri.queryParameters.containsKey('exp'), isFalse);
  });

  test('carries exp when an expiry is set and isExpired reports honestly', () {
    final past = DateTime.utc(2020);
    final future = DateTime.now().toUtc().add(const Duration(days: 1));

    final expiredLink = GroupInviteLink(groupId: 'g1', token: 'tok', secret: secret, expiresAt: past);
    expect(expiredLink.isExpired(), isTrue);

    final freshLink = GroupInviteLink(groupId: 'g1', token: 'tok', secret: secret, expiresAt: future);
    expect(freshLink.isExpired(), isFalse);

    final uri = encodeGroupInviteLink(freshLink);
    final decoded = decodeGroupInviteLink(uri.toString()) as GroupInviteDecoded;
    expect(decoded.link.expiresAt, isNotNull);
    expect(decoded.link.isExpired(), isFalse);
  });

  test('decode refuses a malformed URI', () {
    final result = decodeGroupInviteLink('not a uri at all::::');
    expect(result, isA<GroupInviteDecodeFailure>());
  });

  test('decode refuses the wrong scheme/host/version', () {
    expect(decodeGroupInviteLink('https://join?v=2&g=g1&t=t&s=AAAA'), isA<GroupInviteDecodeFailure>());
    expect(decodeGroupInviteLink('keryx://other?v=2&g=g1&t=t&s=AAAA'), isA<GroupInviteDecodeFailure>());
    expect(decodeGroupInviteLink('keryx://join?v=1&g=g1&t=t&s=AAAA'), isA<GroupInviteDecodeFailure>());
  });

  test('decode refuses a missing group id, token, or secret', () {
    expect(decodeGroupInviteLink('keryx://join?v=2&t=t&s=AAAA'), isA<GroupInviteDecodeFailure>());
    expect(decodeGroupInviteLink('keryx://join?v=2&g=g1&s=AAAA'), isA<GroupInviteDecodeFailure>());
    expect(decodeGroupInviteLink('keryx://join?v=2&g=g1&t=t'), isA<GroupInviteDecodeFailure>());
  });

  test('decode refuses a secret that is not 32 bytes', () {
    final shortLink = GroupInviteLink(groupId: 'g1', token: 'tok', secret: const [1, 2, 3]);
    final uri = encodeGroupInviteLink(shortLink);
    final result = decodeGroupInviteLink(uri.toString());
    expect(result, isA<GroupInviteDecodeFailure>());
  });

  test('decode refuses a malformed exp', () {
    final uri = Uri(
      scheme: groupInviteLinkScheme,
      host: groupInviteLinkHost,
      queryParameters: {'v': '2', 'g': 'g1', 't': 'tok', 's': 'AAAA', 'exp': 'not-a-number'},
    );
    expect(decodeGroupInviteLink(uri.toString()), isA<GroupInviteDecodeFailure>());
  });
}
