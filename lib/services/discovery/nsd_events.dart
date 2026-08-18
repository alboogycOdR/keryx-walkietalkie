import 'discovered_peer.dart';

sealed class NsdEvent {
  const NsdEvent();
}

final class NsdRegistered extends NsdEvent {
  const NsdRegistered({required this.serviceName, required this.port});
  final String serviceName;
  final int port;
}

final class NsdBrowseStarted extends NsdEvent {
  const NsdBrowseStarted();
}

final class NsdPeerFound extends NsdEvent {
  const NsdPeerFound(this.peer);
  final DiscoveredPeer peer;
}

final class NsdPeerLost extends NsdEvent {
  const NsdPeerLost({required this.serviceName});
  final String serviceName;
}

final class NsdLockChanged extends NsdEvent {
  const NsdLockChanged({required this.held});
  final bool held;
}

final class NsdFailed extends NsdEvent {
  const NsdFailed(this.message);
  final String message;
}

NsdEvent? nsdEventFromMap(Map<Object?, Object?> raw) {
  final map = Map<String, dynamic>.from(raw);
  switch (map['type']) {
    case 'registered':
      return NsdRegistered(
        serviceName: map['serviceName'] as String? ?? '',
        port: (map['port'] as num?)?.toInt() ?? 0,
      );
    case 'browseStarted':
      return const NsdBrowseStarted();
    case 'peerFound':
      final peerId = map['peerId'] as String?;
      final cs = map['callsign'] as String?;
      final ch = map['channelHashPrefix'] as String?;
      final version = (map['version'] as num?)?.toInt();
      final port = (map['port'] as num?)?.toInt();
      if (cs == null || cs.isEmpty || ch == null || ch.isEmpty) return null;
      if (version == null || port == null) return null;
      return NsdPeerFound(
        DiscoveredPeer(
          peerId: peerId,
          callsign: cs,
          channelHashPrefix: ch,
          version: version,
          host: map['host'] as String?,
          port: port,
        ),
      );
    case 'peerLost':
      return NsdPeerLost(serviceName: map['serviceName'] as String? ?? '');
    case 'lock':
      return NsdLockChanged(held: map['held'] == true);
    case 'error':
      return NsdFailed(map['message'] as String? ?? 'nsd error');
    default:
      return null;
  }
}
