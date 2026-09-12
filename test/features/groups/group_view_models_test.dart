import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/groups/group_models.dart' show GroupMembership;
import 'package:keryx/features/groups/group_view_models.dart';
import 'package:keryx/services/directory/directory_models.dart' show DirectoryGroupMember;

DirectoryGroupMember _member(String pk, {String role = 'member', String? status}) =>
    DirectoryGroupMember(pk: pk, callsign: pk, role: role, status: status);

void main() {
  group('onlineCountOf', () {
    test('counts every non-offline, non-null status', () {
      final members = [
        _member('a', status: 'available'),
        _member('b', status: 'busy'),
        _member('c', status: 'dnd'),
        _member('d', status: 'offline'),
        _member('e'),
      ];
      expect(onlineCountOf(members), 3);
    });

    test('empty list is zero', () {
      expect(onlineCountOf(const []), 0);
    });
  });

  group('buildGroupListRow', () {
    final membership = GroupMembership(
      id: 'g1',
      name: 'Site crew',
      role: 'admin',
      keyVersion: 1,
      secret: const [1, 2, 3],
      roomId: 'room1',
    );

    test('never fabricates a count when members is null', () {
      final row = buildGroupListRow(membership);
      expect(row.onlineCount, 0);
      expect(row.totalCount, 0);
      expect(row.isAdmin, isTrue);
      expect(row.glyph, 'S');
    });

    test('reflects real counts once members are known', () {
      final row = buildGroupListRow(
        membership,
        members: [
          _member('a', status: 'available'),
          _member('b', status: 'offline'),
        ],
      );
      expect(row.onlineCount, 1);
      expect(row.totalCount, 2);
    });

    test('glyph falls back to ? for an empty name', () {
      final row = buildGroupListRow(membership.copyWith(name: ''));
      expect(row.glyph, '?');
    });
  });

  group('buildMemberRows', () {
    test('admins sort before members, then alphabetical', () {
      final rows = buildMemberRows(
        [
          _member('z', role: 'member', status: 'available'),
          _member('a', role: 'admin', status: 'available'),
          _member('m', role: 'member', status: 'offline'),
        ],
        myPk: 'z',
      );
      expect(rows.map((r) => r.pk).toList(), ['a', 'm', 'z']);
      expect(rows.first.isAdmin, isTrue);
      expect(rows.last.isMe, isTrue);
    });

    test('isOnline is false for offline and for unknown status', () {
      final rows = buildMemberRows(
        [_member('a', status: 'offline'), _member('b', status: null), _member('c', status: 'busy')],
        myPk: 'x',
      );
      final byPk = {for (final r in rows) r.pk: r};
      expect(byPk['a']!.isOnline, isFalse);
      expect(byPk['b']!.isOnline, isFalse);
      expect(byPk['c']!.isOnline, isTrue);
    });
  });

  group('presenceDotStateFor / presenceDotLabel', () {
    test('maps every known wire status', () {
      expect(presenceDotStateFor('available'), PresenceDotState.available);
      expect(presenceDotStateFor('busy'), PresenceDotState.busy);
      expect(presenceDotStateFor('dnd'), PresenceDotState.dnd);
      expect(presenceDotStateFor('offline'), PresenceDotState.offline);
    });

    test('unknown/null status falls back to offline rather than throwing', () {
      expect(presenceDotStateFor(null), PresenceDotState.offline);
      expect(presenceDotStateFor('bogus'), PresenceDotState.offline);
    });

    test('every state has a non-empty word (colour is never the only cue)', () {
      for (final state in PresenceDotState.values) {
        expect(presenceDotLabel(state), isNotEmpty);
      }
    });
  });

  group('isLastAdmin', () {
    test('true only when exactly one admin and it is me', () {
      expect(isLastAdmin([_member('a', role: 'admin')], 'a'), isTrue);
      expect(
        isLastAdmin([_member('a', role: 'admin'), _member('b', role: 'admin')], 'a'),
        isFalse,
      );
      expect(isLastAdmin([_member('a', role: 'admin')], 'b'), isFalse);
    });
  });

  group('oldestMemberToPromote', () {
    test('picks the first non-admin, non-self member', () {
      final members = [_member('me', role: 'admin'), _member('first'), _member('second')];
      final promotee = oldestMemberToPromote(members, myPk: 'me');
      expect(promotee!.pk, 'first');
    });

    test('falls back to the first non-self member if everyone left is somehow already admin', () {
      final members = [_member('me', role: 'admin'), _member('other', role: 'admin')];
      final promotee = oldestMemberToPromote(members, myPk: 'me');
      expect(promotee!.pk, 'other');
    });

    test('returns null for a solo membership', () {
      final promotee = oldestMemberToPromote([_member('me', role: 'admin')], myPk: 'me');
      expect(promotee, isNull);
    });
  });

  group('isGroupFull', () {
    test('true at and above the cap', () {
      expect(isGroupFull(groupMemberCap), isTrue);
      expect(isGroupFull(groupMemberCap + 1), isTrue);
      expect(isGroupFull(groupMemberCap - 1), isFalse);
    });
  });
}
