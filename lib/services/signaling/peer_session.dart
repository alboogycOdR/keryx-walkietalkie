/// An established signaling session with one remote peer.
class PeerSession {
  PeerSession({
    required this.peerId,
    required this.callsign,
    required this.host,
    required this.port,
    required this.lastPresenceAt,
    this.lastSeq = 0,
  });

  final String peerId;
  String callsign;
  final String host;
  final int port;
  DateTime lastPresenceAt;
  int lastSeq;

  PeerSession copyWith({
    String? callsign,
    DateTime? lastPresenceAt,
    int? lastSeq,
  }) {
    return PeerSession(
      peerId: peerId,
      callsign: callsign ?? this.callsign,
      host: host,
      port: port,
      lastPresenceAt: lastPresenceAt ?? this.lastPresenceAt,
      lastSeq: lastSeq ?? this.lastSeq,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PeerSession &&
        other.peerId == peerId &&
        other.callsign == callsign &&
        other.host == host &&
        other.port == port &&
        other.lastPresenceAt == lastPresenceAt &&
        other.lastSeq == lastSeq;
  }

  @override
  int get hashCode =>
      Object.hash(peerId, callsign, host, port, lastPresenceAt, lastSeq);

  @override
  String toString() =>
      'PeerSession($peerId cs=$callsign $host:$port seq=$lastSeq)';
}
