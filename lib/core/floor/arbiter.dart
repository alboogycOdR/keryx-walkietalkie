import 'package:keryx/core/protocol/protocol.dart';

/// Deterministic arbiter election and grant/deny decision (TS §8.3 step 4,
/// §8.6). Pure: no clock, no I/O.
abstract final class Arbiter {
  /// Lexicographically lowest peer ID currently in the channel.
  ///
  /// Returns `null` when [peerIds] is empty. Callsigns are display-only
  /// and must not be passed here (TS §8.6).
  static String? elect(Iterable<String> peerIds) {
    String? best;
    for (final id in peerIds) {
      if (id.isEmpty) continue;
      if (best == null || id.compareTo(best) < 0) {
        best = id;
      }
    }
    return best;
  }

  /// Decide a [TxReq]. Lease expiry is applied first so a crashed
  /// speaker's grant does not block the next requester.
  static ArbiterVerdict decide({
    required String requester,
    required int prio,
    required String? holder,
    required DateTime now,
    required DateTime? leaseExpiresAt,
    required Duration lease,
  }) {
    if (requester.isEmpty) {
      throw ArgumentError.value(requester, 'requester', 'must not be empty');
    }
    if (!FloorPrio.isValid(prio)) {
      throw ArgumentError.value(prio, 'prio', 'must be 0 or 1');
    }
    if (lease.isNegative) {
      throw ArgumentError.value(lease, 'lease', 'must be ≥ 0');
    }

    final liveHolder = _liveHolder(holder, now, leaseExpiresAt);
    if (liveHolder == null || liveHolder == requester) {
      return ArbiterGrant(
        peer: requester,
        lease: lease,
        remaining: liveHolder == requester
            ? _remaining(now, leaseExpiresAt, lease)
            : lease,
        idempotent: liveHolder == requester,
        preempted: null,
      );
    }
    if (prio == FloorPrio.emergency) {
      return ArbiterGrant(
        peer: requester,
        lease: lease,
        remaining: lease,
        idempotent: false,
        preempted: liveHolder,
      );
    }
    return ArbiterDeny(peer: requester, reason: FloorDenyReason.busy);
  }

  /// §8.6 late-joiner self-grant gate. Pure: instants in, bool out.
  ///
  /// A peer may self-grant when the host has declared a solo roster
  /// ([rosterConverged] and [rosterSize] ≤ 1), when it was the first
  /// occupant (others appeared only after a full
  /// [FloorTiming.presenceHeartbeat] of being the sole roster member), or
  /// once that heartbeat has elapsed since [joinedAt].
  ///
  /// Constructor-default `{self}` is **not** aloneness proof:
  /// [rosterConverged] must be true. Roster membership rides the same
  /// delayed/lossy channel as `PRESENCE`; treating "I currently see
  /// nobody" as "I have been alone long enough to be sure" is the hole
  /// TASK-023's soak residual traced. A burst of `PRESENCE` messages
  /// cannot satisfy the elapsed-time branch — it is wall time, not a
  /// message count.
  static bool maySelfGrant({
    required int rosterSize,
    required bool firstOccupant,
    required DateTime joinedAt,
    required DateTime now,
    bool rosterConverged = false,
  }) {
    if (firstOccupant) return true;
    if (rosterSize <= 1 && rosterConverged) return true;
    return !now.isBefore(joinedAt.add(FloorTiming.presenceHeartbeat));
  }

  static String? _liveHolder(
    String? holder,
    DateTime now,
    DateTime? leaseExpiresAt,
  ) {
    if (holder == null || holder.isEmpty) return null;
    if (leaseExpiresAt == null || !now.isBefore(leaseExpiresAt)) return null;
    return holder;
  }

  static Duration _remaining(
    DateTime now,
    DateTime? leaseExpiresAt,
    Duration fallback,
  ) {
    if (leaseExpiresAt == null) return fallback;
    final left = leaseExpiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Result of [Arbiter.decide].
sealed class ArbiterVerdict {
  const ArbiterVerdict({required this.peer});

  final String peer;
}

final class ArbiterGrant extends ArbiterVerdict {
  const ArbiterGrant({
    required super.peer,
    required this.lease,
    required this.remaining,
    required this.idempotent,
    required this.preempted,
  });

  /// Full lease length that would be issued on a fresh grant (`TOT + 2 s`).
  final Duration lease;

  /// Duration written on the wire. Idempotent re-grants keep the original
  /// remaining time so a retry cannot extend TOT.
  final Duration remaining;

  /// `true` when [peer] already holds the live lease.
  final bool idempotent;

  /// Previous holder evicted by `prio=1`, if any.
  final String? preempted;
}

final class ArbiterDeny extends ArbiterVerdict {
  const ArbiterDeny({required super.peer, required this.reason});

  final FloorDenyReason reason;
}
