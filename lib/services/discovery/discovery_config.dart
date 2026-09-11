import 'discovery_constants.dart';

/// Cap on how many rooms one phone advertises at once (Technical §1: "a
/// phone advertises one service per active room (max 3: current target +
/// 2 most recent)").
const maxAdvertisedRooms = 3;

/// Inputs for a LOCAL discovery session. Never includes raw channel/code.
class DiscoveryConfig {
  const DiscoveryConfig({
    required this.peerId,
    required this.callsign,
    required this.channelHashPrefix,
    required this.signalingPort,
    this.protocolVersion = DiscoveryConstants.protocolVersion,
    this.roomPrefixes = const [],
  });

  /// Install peerId — used as the NSD service name.
  final String peerId;

  /// TXT `cs`.
  final String callsign;

  /// TXT `ch`. Must already be a hash prefix (see [ChannelHashPrefix] /
  /// v2's `RoomPrefix`). This is always the *current* target's prefix;
  /// [roomPrefixes] carries the up-to-2 additional rooms Technical §1
  /// wants advertised alongside it (e.g. recently-active groups).
  final String channelHashPrefix;

  /// TXT `v`.
  final int protocolVersion;

  /// LAN signaling WebSocket port advertised as TXT `p` (TASK-020).
  final int signalingPort;

  /// v2 (Technical §1): up to `maxAdvertisedRooms - 1` additional room
  /// prefixes to advertise/resolve alongside [channelHashPrefix] — e.g. the
  /// 2 most-recently-active rooms besides the current target. Each entry
  /// must be produced by `RoomPrefix.compute`/`ChannelHashPrefix.compute`,
  /// non-empty, and distinct from [channelHashPrefix] and each other.
  /// Empty for a v1-style single-room session.
  final List<String> roomPrefixes;

  /// [channelHashPrefix] plus every entry in [roomPrefixes] — the full set
  /// of rooms this session matches peers against / advertises services for.
  List<String> get allRoomPrefixes =>
      List.unmodifiable([channelHashPrefix, ...roomPrefixes]);

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
    if (roomPrefixes.any((p) => p.isEmpty)) {
      throw ArgumentError.value(
        roomPrefixes,
        'roomPrefixes',
        'must not contain an empty prefix',
      );
    }
    final all = allRoomPrefixes;
    if (all.length > maxAdvertisedRooms) {
      throw ArgumentError.value(
        roomPrefixes,
        'roomPrefixes',
        'channelHashPrefix + roomPrefixes must not exceed $maxAdvertisedRooms rooms',
      );
    }
    if (all.toSet().length != all.length) {
      throw ArgumentError.value(
        roomPrefixes,
        'roomPrefixes',
        'must not repeat channelHashPrefix or another entry',
      );
    }
  }

  Map<String, Object> toPlatformArgs() => {
    'peerId': peerId,
    'callsign': callsign,
    'channelHashPrefix': channelHashPrefix,
    'protocolVersion': protocolVersion,
    'signalingPort': signalingPort,
    'serviceType': DiscoveryConstants.serviceType,
    'roomPrefixes': roomPrefixes,
  };
}
