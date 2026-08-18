import 'discovery_constants.dart';

/// Inputs for a LOCAL discovery session. Never includes raw channel/code.
class DiscoveryConfig {
  const DiscoveryConfig({
    required this.peerId,
    required this.callsign,
    required this.channelHashPrefix,
    required this.signalingPort,
    this.protocolVersion = DiscoveryConstants.protocolVersion,
  });

  /// Install peerId — used as the NSD service name.
  final String peerId;

  /// TXT `cs`.
  final String callsign;

  /// TXT `ch`. Must already be a hash prefix (see [ChannelHashPrefix]).
  final String channelHashPrefix;

  /// TXT `v`.
  final int protocolVersion;

  /// LAN signaling WebSocket port advertised as TXT `p` (TASK-020).
  final int signalingPort;

  void validate() {
    if (peerId.isEmpty) {
      throw ArgumentError.value(peerId, 'peerId', 'must be non-empty');
    }
    if (callsign.isEmpty) {
      throw ArgumentError.value(callsign, 'callsign', 'must be non-empty');
    }
    if (channelHashPrefix.isEmpty) {
      throw ArgumentError.value(
        channelHashPrefix,
        'channelHashPrefix',
        'must be non-empty',
      );
    }
    if (channelHashPrefix.contains('|')) {
      throw ArgumentError.value(
        channelHashPrefix,
        'channelHashPrefix',
        'looks like a raw region|ch|code tuple; pass ChannelHashPrefix.compute',
      );
    }
    if (protocolVersion < 1) {
      throw ArgumentError.value(protocolVersion, 'protocolVersion');
    }
    if (signalingPort < 1 || signalingPort > 65535) {
      throw ArgumentError.value(signalingPort, 'signalingPort');
    }
  }

  Map<String, Object> toPlatformArgs() => {
    'peerId': peerId,
    'callsign': callsign,
    'channelHashPrefix': channelHashPrefix,
    'protocolVersion': protocolVersion,
    'signalingPort': signalingPort,
    'serviceType': DiscoveryConstants.serviceType,
  };
}
