/// `TX_REQ.prio` values from TS §8.6: `0` normal, `1` emergency.
abstract final class FloorPrio {
  static const int normal = 0;
  static const int emergency = 1;

  static bool isValid(int prio) => prio == normal || prio == emergency;
}

/// `TX_DENY.reason` wire values: `BUSY` | `LOCKOUT`.
enum FloorDenyReason {
  busy('BUSY'),
  lockout('LOCKOUT');

  const FloorDenyReason(this.wire);

  /// Exact §8.6 token written on the wire.
  final String wire;

  static FloorDenyReason? fromWire(String value) {
    for (final reason in FloorDenyReason.values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

/// Wire `t` tokens — one per TS §8.6 table row (START/END and EMG/CLR split).
abstract final class FloorMsgType {
  static const txReq = 'TX_REQ';
  static const txGrant = 'TX_GRANT';
  static const txDeny = 'TX_DENY';
  static const txStart = 'TX_START';
  static const txEnd = 'TX_END';
  static const presence = 'PRESENCE';
  static const rchk = 'RCHK';
  static const rchkAck = 'RCHK_ACK';
  static const emg = 'EMG';
  static const emgClr = 'EMG_CLR';

  static const List<String> all = [
    txReq,
    txGrant,
    txDeny,
    txStart,
    txEnd,
    presence,
    rchk,
    rchkAck,
    emg,
    emgClr,
  ];
}

/// Floor-control protocol v1 message. Field names on the wire match TS §8.6.
sealed class FloorMessage {
  const FloorMessage({required this.peer});

  /// Device `peerId` (TS §8.6). Present on every message type.
  final String peer;

  /// Wire `t` token.
  String get type;
}

/// `TX_REQ {peer, prio, ts}` — request the floor.
final class TxReq extends FloorMessage {
  const TxReq({required super.peer, required this.prio, required this.ts});

  /// `0` normal / `1` emergency. Emergency pre-empts an active lease.
  final int prio;

  /// Sender timestamp, Unix epoch milliseconds.
  final int ts;

  @override
  String get type => FloorMsgType.txReq;

  @override
  bool operator ==(Object other) =>
      other is TxReq &&
      other.peer == peer &&
      other.prio == prio &&
      other.ts == ts;

  @override
  int get hashCode => Object.hash(type, peer, prio, ts);

  @override
  String toString() => 'TxReq(peer: $peer, prio: $prio, ts: $ts)';
}

/// `TX_GRANT {peer, lease_ms}` — arbiter grants; lease = TOT + 2 s.
final class TxGrant extends FloorMessage {
  const TxGrant({required super.peer, required this.leaseMs});

  /// Lease remaining / granted length, milliseconds.
  final int leaseMs;

  @override
  String get type => FloorMsgType.txGrant;

  @override
  bool operator ==(Object other) =>
      other is TxGrant && other.peer == peer && other.leaseMs == leaseMs;

  @override
  int get hashCode => Object.hash(type, peer, leaseMs);

  @override
  String toString() => 'TxGrant(peer: $peer, leaseMs: $leaseMs)';
}

/// `TX_DENY {peer, reason}` — `BUSY` | `LOCKOUT`.
final class TxDeny extends FloorMessage {
  const TxDeny({required super.peer, required this.reason});

  final FloorDenyReason reason;

  @override
  String get type => FloorMsgType.txDeny;

  @override
  bool operator ==(Object other) =>
      other is TxDeny && other.peer == peer && other.reason == reason;

  @override
  int get hashCode => Object.hash(type, peer, reason);

  @override
  String toString() => 'TxDeny(peer: $peer, reason: ${reason.wire})';
}

/// `TX_START {peer}` — speaker announces; receivers gate audio + drive UI.
final class TxStart extends FloorMessage {
  const TxStart({required super.peer});

  @override
  String get type => FloorMsgType.txStart;

  @override
  bool operator ==(Object other) => other is TxStart && other.peer == peer;

  @override
  int get hashCode => Object.hash(type, peer);

  @override
  String toString() => 'TxStart(peer: $peer)';
}

/// `TX_END {peer}` — speaker releases; receivers ungated.
final class TxEnd extends FloorMessage {
  const TxEnd({required super.peer});

  @override
  String get type => FloorMsgType.txEnd;

  @override
  bool operator ==(Object other) => other is TxEnd && other.peer == peer;

  @override
  int get hashCode => Object.hash(type, peer);

  @override
  String toString() => 'TxEnd(peer: $peer)';
}

/// `PRESENCE {peer, cs, seq, holder?, lease_remaining_ms?}` — 5 s heartbeat;
/// 3 misses = departed. Optional floor-state fields close the late-joiner
/// blind spot (TS §8.6 amendment 2026-08-21).
final class Presence extends FloorMessage {
  const Presence({
    required super.peer,
    required this.cs,
    required this.seq,
    this.holder,
    this.leaseRemainingMs,
  });

  /// Display callsign. Not used in election (TS §8.6).
  final String cs;

  /// Monotonic heartbeat sequence.
  final int seq;

  /// Arbiter/engine view of who holds the floor. Absent when idle.
  /// Present together with [leaseRemainingMs].
  final String? holder;

  /// Milliseconds left on the live lease. Present iff [holder] is present.
  final int? leaseRemainingMs;

  @override
  String get type => FloorMsgType.presence;

  @override
  bool operator ==(Object other) =>
      other is Presence &&
      other.peer == peer &&
      other.cs == cs &&
      other.seq == seq &&
      other.holder == holder &&
      other.leaseRemainingMs == leaseRemainingMs;

  @override
  int get hashCode =>
      Object.hash(type, peer, cs, seq, holder, leaseRemainingMs);

  @override
  String toString() =>
      'Presence(peer: $peer, cs: $cs, seq: $seq, '
      'holder: $holder, leaseRemainingMs: $leaseRemainingMs)';
}

/// `RCHK {peer, quality}` — radio-check ping (FR-066). Zero voice.
final class Rchk extends FloorMessage {
  const Rchk({required super.peer, required this.quality});

  /// Measured link quality as an S-meter integer (TS §8.9: S1–S9).
  final int quality;

  @override
  String get type => FloorMsgType.rchk;

  @override
  bool operator ==(Object other) =>
      other is Rchk && other.peer == peer && other.quality == quality;

  @override
  int get hashCode => Object.hash(type, peer, quality);

  @override
  String toString() => 'Rchk(peer: $peer, quality: $quality)';
}

/// `RCHK_ACK {peer, quality}` — auto-response with the receiver's quality.
final class RchkAck extends FloorMessage {
  const RchkAck({required super.peer, required this.quality});

  /// Measured link quality as an S-meter integer (TS §8.9: S1–S9).
  final int quality;

  @override
  String get type => FloorMsgType.rchkAck;

  @override
  bool operator ==(Object other) =>
      other is RchkAck && other.peer == peer && other.quality == quality;

  @override
  int get hashCode => Object.hash(type, peer, quality);

  @override
  String toString() => 'RchkAck(peer: $peer, quality: $quality)';
}

/// `EMG {peer}` — priority pre-emption pin (FR-025).
final class Emg extends FloorMessage {
  const Emg({required super.peer});

  @override
  String get type => FloorMsgType.emg;

  @override
  bool operator ==(Object other) => other is Emg && other.peer == peer;

  @override
  int get hashCode => Object.hash(type, peer);

  @override
  String toString() => 'Emg(peer: $peer)';
}

/// `EMG_CLR {peer}` — sender clears the EMG pin.
final class EmgClr extends FloorMessage {
  const EmgClr({required super.peer});

  @override
  String get type => FloorMsgType.emgClr;

  @override
  bool operator ==(Object other) => other is EmgClr && other.peer == peer;

  @override
  int get hashCode => Object.hash(type, peer);

  @override
  String toString() => 'EmgClr(peer: $peer)';
}
