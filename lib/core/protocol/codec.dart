import 'dart:convert';

import 'messages.dart';

/// Protocol version carried on every v1 message (`v` in the envelope).
const int kFloorProtocolVersion = 1;

/// JSON codec for floor-control protocol v1 (TS §8.6).
///
/// Envelope: `{v: 1, t: "TX_REQ", ...fields}`.
/// Unknown versions, unknown types, and malformed input decode to `null`
/// (ignored — forward compatibility). [decode] never throws.
abstract final class FloorCodec {
  /// Encode a typed message to a compact JSON string.
  ///
  /// Throws [ArgumentError] if the in-memory message is not wire-legal
  /// (empty peer, prio outside 0/1, empty callsign, negative lease).
  static String encode(FloorMessage message) {
    _requireEncodable(message);
    final body = <String, Object>{
      'v': kFloorProtocolVersion,
      't': message.type,
    };
    switch (message) {
      case TxReq(:final peer, :final prio, :final ts):
        body['peer'] = peer;
        body['prio'] = prio;
        body['ts'] = ts;
      case TxGrant(:final peer, :final leaseMs):
        body['peer'] = peer;
        body['lease_ms'] = leaseMs;
      case TxDeny(:final peer, :final reason):
        body['peer'] = peer;
        body['reason'] = reason.wire;
      case TxStart(:final peer):
        body['peer'] = peer;
      case TxEnd(:final peer):
        body['peer'] = peer;
      case Presence(:final peer, :final cs, :final seq):
        body['peer'] = peer;
        body['cs'] = cs;
        body['seq'] = seq;
      case Rchk(:final peer, :final quality):
        body['peer'] = peer;
        body['quality'] = quality;
      case RchkAck(:final peer, :final quality):
        body['peer'] = peer;
        body['quality'] = quality;
      case Emg(:final peer):
        body['peer'] = peer;
      case EmgClr(:final peer):
        body['peer'] = peer;
    }
    return jsonEncode(body);
  }

  /// Decode a wire string. Returns `null` to ignore (never throws).
  static FloorMessage? decode(String wire) {
    try {
      final decoded = jsonDecode(wire);
      if (decoded is! Map) return null;
      final map = <String, dynamic>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      if (map.length != decoded.length) return null;

      final version = _asInt(map['v']);
      if (version == null) return null;
      // Unknown versions are ignored (TS §8.6 forward compatibility).
      if (version != kFloorProtocolVersion) return null;

      final type = map['t'];
      if (type is! String) return null;

      final peer = _asNonEmptyString(map['peer']);
      if (peer == null) return null;

      switch (type) {
        case FloorMsgType.txReq:
          final prio = _asInt(map['prio']);
          final ts = _asInt(map['ts']);
          if (prio == null || !FloorPrio.isValid(prio) || ts == null) {
            return null;
          }
          return TxReq(peer: peer, prio: prio, ts: ts);
        case FloorMsgType.txGrant:
          final leaseMs = _asInt(map['lease_ms']);
          if (leaseMs == null || leaseMs < 0) return null;
          return TxGrant(peer: peer, leaseMs: leaseMs);
        case FloorMsgType.txDeny:
          final reasonRaw = map['reason'];
          if (reasonRaw is! String) return null;
          final reason = FloorDenyReason.fromWire(reasonRaw);
          if (reason == null) return null;
          return TxDeny(peer: peer, reason: reason);
        case FloorMsgType.txStart:
          return TxStart(peer: peer);
        case FloorMsgType.txEnd:
          return TxEnd(peer: peer);
        case FloorMsgType.presence:
          final cs = _asNonEmptyString(map['cs']);
          final seq = _asInt(map['seq']);
          if (cs == null || seq == null) return null;
          return Presence(peer: peer, cs: cs, seq: seq);
        case FloorMsgType.rchk:
          final quality = _asInt(map['quality']);
          if (quality == null) return null;
          return Rchk(peer: peer, quality: quality);
        case FloorMsgType.rchkAck:
          final quality = _asInt(map['quality']);
          if (quality == null) return null;
          return RchkAck(peer: peer, quality: quality);
        case FloorMsgType.emg:
          return Emg(peer: peer);
        case FloorMsgType.emgClr:
          return EmgClr(peer: peer);
        default:
          // Unknown type — ignore (forward compatibility).
          return null;
      }
    } on Object {
      return null;
    }
  }

  static void _requireEncodable(FloorMessage message) {
    if (message.peer.isEmpty) {
      throw ArgumentError.value(message.peer, 'peer', 'must be non-empty');
    }
    switch (message) {
      case TxReq(:final prio):
        if (!FloorPrio.isValid(prio)) {
          throw ArgumentError.value(
            prio,
            'prio',
            'must be 0 (normal) or 1 (emergency)',
          );
        }
      case TxGrant(:final leaseMs):
        if (leaseMs < 0) {
          throw ArgumentError.value(leaseMs, 'leaseMs', 'must be >= 0');
        }
      case Presence(:final cs):
        if (cs.isEmpty) {
          throw ArgumentError.value(cs, 'cs', 'must be non-empty');
        }
      case TxDeny() ||
            TxStart() ||
            TxEnd() ||
            Rchk() ||
            RchkAck() ||
            Emg() ||
            EmgClr():
        break;
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble() && value.isFinite) {
      return value.toInt();
    }
    return null;
  }

  static String? _asNonEmptyString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }
}
