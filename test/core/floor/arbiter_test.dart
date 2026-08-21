import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/protocol/protocol.dart';

void main() {
  group('Arbiter.elect', () {
    test('lowest peerId wins', () {
      expect(
        Arbiter.elect(const ['MMM2222222', 'AAA2222222', 'ZZZ2222222']),
        'AAA2222222',
      );
    });

    test('single peer elects itself', () {
      expect(Arbiter.elect(const ['MMM2222222']), 'MMM2222222');
    });

    test('empty roster is null', () {
      expect(Arbiter.elect(const <String>[]), isNull);
    });

    test('empty strings are ignored', () {
      expect(Arbiter.elect(const ['', 'BBB2222222', '']), 'BBB2222222');
    });

    test('lexicographic, not insertion order', () {
      expect(Arbiter.elect(const ['Z', 'A', 'M']), 'A');
      expect(Arbiter.elect(const ['A', 'M', 'Z']), 'A');
    });
  });

  group('Arbiter.decide', () {
    final now = DateTime.utc(2026, 1, 1);
    final lease = FloorTiming.defaultGrantLease;

    test('grants when floor is free', () {
      final v = Arbiter.decide(
        requester: 'BBB2222222',
        prio: FloorPrio.normal,
        holder: null,
        now: now,
        leaseExpiresAt: null,
        lease: lease,
      );
      expect(
        v,
        isA<ArbiterGrant>()
            .having((g) => g.peer, 'peer', 'BBB2222222')
            .having((g) => g.idempotent, 'idempotent', isFalse)
            .having((g) => g.remaining, 'remaining', lease)
            .having((g) => g.preempted, 'preempted', isNull),
      );
    });

    test('expired lease is treated as free', () {
      final v = Arbiter.decide(
        requester: 'BBB2222222',
        prio: FloorPrio.normal,
        holder: 'AAA2222222',
        now: now,
        leaseExpiresAt: now,
        lease: lease,
      );
      expect(
        v,
        isA<ArbiterGrant>().having((g) => g.peer, 'peer', 'BBB2222222'),
      );
    });

    test('idempotent re-grant keeps remaining lease', () {
      final expires = now.add(const Duration(seconds: 40));
      final v = Arbiter.decide(
        requester: 'AAA2222222',
        prio: FloorPrio.normal,
        holder: 'AAA2222222',
        now: now,
        leaseExpiresAt: expires,
        lease: lease,
      );
      expect(
        v,
        isA<ArbiterGrant>()
            .having((g) => g.idempotent, 'idempotent', isTrue)
            .having(
              (g) => g.remaining,
              'remaining',
              const Duration(seconds: 40),
            )
            .having((g) => g.lease, 'lease', lease),
      );
    });

    test('busy deny when another holder is live', () {
      final v = Arbiter.decide(
        requester: 'BBB2222222',
        prio: FloorPrio.normal,
        holder: 'AAA2222222',
        now: now,
        leaseExpiresAt: now.add(lease),
        lease: lease,
      );
      expect(
        v,
        isA<ArbiterDeny>()
            .having((d) => d.peer, 'peer', 'BBB2222222')
            .having((d) => d.reason, 'reason', FloorDenyReason.busy),
      );
    });

    test('emergency pre-empts a live lease', () {
      final v = Arbiter.decide(
        requester: 'CCC2222222',
        prio: FloorPrio.emergency,
        holder: 'AAA2222222',
        now: now,
        leaseExpiresAt: now.add(lease),
        lease: lease,
      );
      expect(
        v,
        isA<ArbiterGrant>()
            .having((g) => g.peer, 'peer', 'CCC2222222')
            .having((g) => g.preempted, 'preempted', 'AAA2222222')
            .having((g) => g.idempotent, 'idempotent', isFalse)
            .having((g) => g.remaining, 'remaining', lease),
      );
    });

    test('maySelfGrant is elapsed-time, not a message count', () {
      final joined = DateTime.utc(2026, 1, 1);
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 1,
          firstOccupant: false,
          joinedAt: joined,
          now: joined,
        ),
        isFalse,
        reason: 'constructor-default {self} is not aloneness proof',
      );
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 1,
          firstOccupant: false,
          joinedAt: joined,
          now: joined,
          rosterConverged: true,
        ),
        isTrue,
        reason: 'host-declared solo roster is genuine convergence',
      );
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 2,
          firstOccupant: true,
          joinedAt: joined,
          now: joined,
        ),
        isTrue,
      );
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 2,
          firstOccupant: false,
          joinedAt: joined,
          now: joined.add(const Duration(seconds: 4, milliseconds: 999)),
        ),
        isFalse,
      );
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 2,
          firstOccupant: false,
          joinedAt: joined,
          now: joined.add(FloorTiming.presenceHeartbeat),
        ),
        isTrue,
      );
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 2,
          firstOccupant: false,
          joinedAt: joined,
          now: joined.add(FloorTiming.presenceHeartbeat),
          linkReachable: false,
        ),
        isFalse,
        reason: 'partition pause: wall time without a live link does not count',
      );
      final healed = joined.add(const Duration(seconds: 8));
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 2,
          firstOccupant: false,
          joinedAt: joined,
          now: healed,
          observingSince: healed,
        ),
        isFalse,
        reason: 'heal restarts the observation window',
      );
      expect(
        Arbiter.maySelfGrant(
          rosterSize: 2,
          firstOccupant: false,
          joinedAt: joined,
          now: healed.add(FloorTiming.presenceHeartbeat),
          observingSince: healed,
        ),
        isTrue,
      );
    });

    test('rejects illegal prio / empty requester / negative lease', () {
      expect(
        () => Arbiter.decide(
          requester: '',
          prio: 0,
          holder: null,
          now: now,
          leaseExpiresAt: null,
          lease: lease,
        ),
        throwsArgumentError,
      );
      expect(
        () => Arbiter.decide(
          requester: 'AAA2222222',
          prio: 2,
          holder: null,
          now: now,
          leaseExpiresAt: null,
          lease: lease,
        ),
        throwsArgumentError,
      );
      expect(
        () => Arbiter.decide(
          requester: 'AAA2222222',
          prio: 0,
          holder: null,
          now: now,
          leaseExpiresAt: null,
          lease: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });
}
