import 'discovery_constants.dart';

/// v2 LAN discovery match key (Technical §1, §5.1): the first
/// [DiscoveryConstants.channelHashPrefixLength] characters of a v2 room ID
/// (`lib/core/rooms/derivation.dart`'s `deriveGroupRoom`/`deriveDirectRoom`).
///
/// Room IDs are already opaque RFC 4648 base32 HMAC/scrypt output, so no
/// further hashing is needed: slicing the room ID directly cannot leak
/// anything the room ID itself doesn't already reveal.
abstract final class RoomPrefix {
  static String compute(String roomId) {
    if (roomId.isEmpty) {
      throw ArgumentError.value(roomId, 'roomId', 'must be non-empty');
    }
    if (roomId.length < DiscoveryConstants.channelHashPrefixLength) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'must be at least ${DiscoveryConstants.channelHashPrefixLength} characters',
      );
    }
    return roomId.substring(0, DiscoveryConstants.channelHashPrefixLength);
  }
}
