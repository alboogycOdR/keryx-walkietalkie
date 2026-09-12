import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/talk_target.dart';

void main() {
  group('TalkTarget', () {
    test('value equality/hashCode over every field', () {
      const a = TalkTarget(
        kind: TalkTargetKind.contact,
        id: 'p1',
        name: 'Alpha',
        roomId: 'room-1',
        memberPeerIds: ['p2'],
      );
      const b = TalkTarget(
        kind: TalkTargetKind.contact,
        id: 'p1',
        name: 'Alpha',
        roomId: 'room-1',
        memberPeerIds: ['p2'],
      );
      const differentMembers = TalkTarget(
        kind: TalkTargetKind.contact,
        id: 'p1',
        name: 'Alpha',
        roomId: 'room-1',
        memberPeerIds: ['p3'],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(differentMembers));
    });
  });

  group('AudienceState.compute', () {
    test('a null target returns everyoneReachable (v1-safe default)', () {
      final audience = AudienceState.compute(
        target: null,
        presenceByPeerId: const {},
      );
      expect(audience, AudienceState.everyoneReachable);
      expect(audience.canHear, 1);
      expect(audience.reason, isNull);
    });

    test('an empty-roster target always reads Nobody is listening', () {
      const target = TalkTarget(
        kind: TalkTargetKind.group,
        id: 'g1',
        name: 'Solo Group',
        roomId: 'room-solo',
      );
      final audience = AudienceState.compute(
        target: target,
        presenceByPeerId: const {},
      );
      expect(audience.canHear, 0);
      expect(audience.reason, 'Nobody is listening');
    });

    test('a contact target: online counts, offline/dnd/busy do not', () {
      const contact = TalkTarget(
        kind: TalkTargetKind.contact,
        id: 'p1',
        name: 'Bravo',
        roomId: 'room-1',
        memberPeerIds: ['p1'],
      );

      expect(
        AudienceState.compute(
          target: contact,
          presenceByPeerId: const {'p1': PeerPresence.online},
        ),
        const AudienceState(canHear: 1, reason: null),
      );
      expect(
        AudienceState.compute(
          target: contact,
          presenceByPeerId: const {'p1': PeerPresence.offline},
        ),
        const AudienceState(canHear: 0, reason: 'Bravo is offline'),
      );
      expect(
        AudienceState.compute(
          target: contact,
          presenceByPeerId: const {'p1': PeerPresence.dnd},
        ),
        const AudienceState(canHear: 0, reason: 'Bravo has Do Not Disturb on'),
      );
      expect(
        AudienceState.compute(
          target: contact,
          presenceByPeerId: const {'p1': PeerPresence.busy},
        ),
        const AudienceState(canHear: 0, reason: 'Bravo is busy'),
      );
      // Missing from the map defaults to offline, not a crash.
      expect(
        AudienceState.compute(
          target: contact,
          presenceByPeerId: const {},
        ),
        const AudienceState(canHear: 0, reason: 'Bravo is offline'),
      );
    });

    test('a group target: mixed presence counts only the online members', () {
      const group = TalkTarget(
        kind: TalkTargetKind.group,
        id: 'g1',
        name: 'Charlie Group',
        roomId: 'room-g',
        memberPeerIds: ['p1', 'p2', 'p3'],
      );

      final mixed = AudienceState.compute(
        target: group,
        presenceByPeerId: const {
          'p1': PeerPresence.online,
          'p2': PeerPresence.offline,
          'p3': PeerPresence.busy,
        },
      );
      expect(mixed.canHear, 1);
      expect(mixed.reason, isNull);

      final allOffline = AudienceState.compute(
        target: group,
        presenceByPeerId: const {
          'p1': PeerPresence.offline,
          'p2': PeerPresence.offline,
          'p3': PeerPresence.offline,
        },
      );
      expect(allOffline, const AudienceState(canHear: 0, reason: 'Nobody is listening'));

      final allDnd = AudienceState.compute(
        target: group,
        presenceByPeerId: const {
          'p1': PeerPresence.dnd,
          'p2': PeerPresence.dnd,
          'p3': PeerPresence.dnd,
        },
      );
      expect(
        allDnd,
        const AudienceState(canHear: 0, reason: 'Everyone has Do Not Disturb on'),
      );

      final allBusy = AudienceState.compute(
        target: group,
        presenceByPeerId: const {
          'p1': PeerPresence.busy,
          'p2': PeerPresence.busy,
          'p3': PeerPresence.busy,
        },
      );
      expect(allBusy, const AudienceState(canHear: 0, reason: 'Everyone is busy'));

      final mixedZeroOnline = AudienceState.compute(
        target: group,
        presenceByPeerId: const {
          'p1': PeerPresence.offline,
          'p2': PeerPresence.dnd,
          'p3': PeerPresence.busy,
        },
      );
      expect(
        mixedZeroOnline,
        const AudienceState(canHear: 0, reason: 'Nobody is listening'),
      );
    });
  });
}
