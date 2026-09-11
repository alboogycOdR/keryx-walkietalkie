import 'discovery_constants.dart';

/// v2 LAN discovery match key (Technical §1, §5.1): the first
/// [DiscoveryConstants.channelHashPrefixLength] characters of a v2 room ID
/// (`lib/core/rooms/derivation.dart`'s `deriveGroupRoom`/`deriveDirectRoom`).
///
/// Room IDs are already opaque RFC 4648 base32 HMAC/scrypt output, so unlike
/// the legacy [ChannelHashPrefix] — which hashed a plaintext region/channel/
/// code tuple specifically to keep it off the wire — no further hashing is
/// needed here: slicing the room ID directly cannot leak anything the room
/// ID itself doesn't already reveal (nothing; it's already a one-way digest
/// of the group secret / shared X25519 secret).
///
/// Retained alongside [ChannelHashPrefix] (see that file's dartdoc) until
/// TASK-088 migrates `RadioSessionController` off numbered channels
/// (Technical §10 item 11, "Deletions ... after 10") — the only remaining
/// caller of the legacy prefix, and outside this task's `Owned_Paths`.
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
