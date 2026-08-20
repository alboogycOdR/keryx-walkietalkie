import 'dart:convert';

import 'ice_filter.dart';
import 'signaling_constants.dart';

/// Signaling `type` tokens. Distinct from floor-control `t` (TASK-006).
enum SignalingType {
  hello('hello'),
  helloOk('hello-ok'),
  offer('offer'),
  answer('answer'),
  iceCandidate('ice-candidate');

  const SignalingType(this.wire);

  /// Exact token written on the wire.
  final String wire;

  static SignalingType? fromWire(String value) {
    for (final type in SignalingType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// WebRTC / handshake envelope v1. Spec-silent shape, pinned in README.
///
/// Wire: `{v, type, from, to, payload}`. [decode] never throws.
class SignalingEnvelope {
  const SignalingEnvelope({
    required this.type,
    required this.from,
    required this.to,
    required this.payload,
    this.version = SignalingConstants.envelopeVersion,
  });

  final int version;
  final SignalingType type;
  final String from;
  final String to;
  final Map<String, Object?> payload;

  String? get sdp {
    final value = payload['sdp'];
    return value is String ? value : null;
  }

  String? get candidate {
    final value = payload['candidate'];
    return value is String ? value : null;
  }

  String? get callsign {
    final value = payload['cs'];
    return value is String ? value : null;
  }

  String? get channelHash {
    final value = payload['ch'];
    return value is String ? value : null;
  }

  /// Encode to compact JSON. Throws if the in-memory envelope is illegal.
  String encode() {
    if (from.isEmpty) {
      throw ArgumentError.value(from, 'from', 'must be non-empty');
    }
    if (type != SignalingType.hello &&
        type != SignalingType.helloOk &&
        to.isEmpty) {
      throw ArgumentError.value(to, 'to', 'must be non-empty');
    }
    return jsonEncode({
      'v': version,
      'type': type.wire,
      'from': from,
      'to': to,
      'payload': payload,
    });
  }

  /// Decode a wire string. Returns `null` to ignore (never throws).
  static SignalingEnvelope? decode(String wire) {
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
      if (version != SignalingConstants.envelopeVersion) return null;

      final typeRaw = map['type'];
      if (typeRaw is! String) return null;
      final type = SignalingType.fromWire(typeRaw);
      if (type == null) return null;

      final from = _asNonEmptyString(map['from']);
      if (from == null) return null;

      final to = map['to'];
      if (to is! String) return null;
      if (type != SignalingType.hello &&
          type != SignalingType.helloOk &&
          to.isEmpty) {
        return null;
      }

      final payloadRaw = map['payload'];
      if (payloadRaw is! Map) return null;
      final payload = <String, Object?>{
        for (final entry in payloadRaw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };

      if (!_payloadLegal(type, payload)) return null;

      return SignalingEnvelope(
        version: version,
        type: type,
        from: from,
        to: to,
        payload: Map.unmodifiable(payload),
      );
    } on Object {
      return null;
    }
  }

  static bool _payloadLegal(SignalingType type, Map<String, Object?> payload) {
    switch (type) {
      case SignalingType.hello:
      case SignalingType.helloOk:
        return _asNonEmptyString(payload['cs']) != null &&
            _asNonEmptyString(payload['ch']) != null;
      case SignalingType.offer:
      case SignalingType.answer:
        return _asNonEmptyString(payload['sdp']) != null;
      case SignalingType.iceCandidate:
        return _asNonEmptyString(payload['candidate']) != null;
    }
  }

  /// Drop non-LAN ICE from an offer/answer/ICE envelope. Returns `null`
  /// when an ICE candidate itself is not LAN-legal (caller should not send).
  SignalingEnvelope? lanFiltered() {
    switch (type) {
      case SignalingType.iceCandidate:
        final cand = candidate;
        if (cand == null || !isLanIceCandidate(cand)) return null;
        return this;
      case SignalingType.offer:
      case SignalingType.answer:
        final raw = sdp;
        if (raw == null) return null;
        final cleaned = sanitizeSdp(raw);
        if (cleaned == raw) return this;
        return SignalingEnvelope(
          version: version,
          type: type,
          from: from,
          to: to,
          payload: {'sdp': cleaned},
        );
      case SignalingType.hello:
      case SignalingType.helloOk:
        return this;
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

  @override
  bool operator ==(Object other) {
    return other is SignalingEnvelope &&
        other.version == version &&
        other.type == type &&
        other.from == from &&
        other.to == to &&
        _mapEquals(other.payload, payload);
  }

  @override
  int get hashCode => Object.hash(version, type, from, to, payload.length);

  @override
  String toString() =>
      'SignalingEnvelope(${type.wire} $from->$to payload=$payload)';
}

bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
}
