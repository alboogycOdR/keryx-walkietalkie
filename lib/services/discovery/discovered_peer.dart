/// A LOCAL peer observed via NSD or the UDP beacon fallback.
class DiscoveredPeer {
  const DiscoveredPeer({
    this.peerId,
    required this.callsign,
    required this.channelHashPrefix,
    required this.version,
    this.host,
    required this.port,
    this.source = DiscoverySource.nsd,
  });

  /// NSD service name / install peerId. Absent on a malformed beacon.
  final String? peerId;

  /// TXT `cs`. Display only.
  final String callsign;

  /// TXT `ch` — hash prefix, never plaintext channel/code.
  final String channelHashPrefix;

  /// TXT `v`.
  final int version;

  /// Resolved host (NSD) or datagram source (UDP).
  final String? host;

  /// Signaling port (TXT `p` / NSD service port). TASK-020 consumes this.
  final int port;

  final DiscoverySource source;

  bool matchesChannel(String prefix) => channelHashPrefix == prefix;

  DiscoveredPeer copyWith({
    String? peerId,
    String? callsign,
    String? channelHashPrefix,
    int? version,
    String? host,
    int? port,
    DiscoverySource? source,
  }) {
    return DiscoveredPeer(
      peerId: peerId ?? this.peerId,
      callsign: callsign ?? this.callsign,
      channelHashPrefix: channelHashPrefix ?? this.channelHashPrefix,
      version: version ?? this.version,
      host: host ?? this.host,
      port: port ?? this.port,
      source: source ?? this.source,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DiscoveredPeer &&
        other.peerId == peerId &&
        other.callsign == callsign &&
        other.channelHashPrefix == channelHashPrefix &&
        other.version == version &&
        other.host == host &&
        other.port == port &&
        other.source == source;
  }

  @override
  int get hashCode => Object.hash(
    peerId,
    callsign,
    channelHashPrefix,
    version,
    host,
    port,
    source,
  );

  @override
  String toString() =>
      'DiscoveredPeer($peerId cs=$callsign ch=$channelHashPrefix '
      '$host:$port via $source)';
}

enum DiscoverySource { nsd, udp }
