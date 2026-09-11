import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'discovery_constants.dart';

/// Privacy prefix for NSD TXT `ch` / UDP beacons (TS §8.3 step 1).
///
/// Computes `hex(SHA-256(utf8("$region|$channel|$code")))[:8]`.
/// This is **not** the §8.7 roomId (`b32(HMAC-SHA256(...))[:16]`, TASK-007).
/// LOCAL discovery only needs a stable match key that never puts plaintext
/// channel or privacy-code on the wire. When TASK-007 lands, callers may pass
/// `roomId.substring(0, 8)` instead; the facade accepts an opaque prefix.
///
/// **v2 (TASK-087):** `roomId.substring(0, 8)` now exists as
/// `RoomPrefix.compute` (`room_prefix.dart`) for the new group/1:1 room
/// derivation. This class is retained only because
/// `lib/services/session/radio_session_controller.dart` (outside TASK-087's
/// `Owned_Paths`) still calls it for numbered channels; do not add new
/// callers — use `RoomPrefix` instead.
abstract final class ChannelHashPrefix {
  static String compute({
    required String region,
    required String channel,
    required String code,
  }) {
    if (region.isEmpty) {
      throw ArgumentError.value(region, 'region', 'must be non-empty');
    }
    if (channel.isEmpty) {
      throw ArgumentError.value(channel, 'channel', 'must be non-empty');
    }
    final digest = sha256.convert(utf8.encode('$region|$channel|$code'));
    return digest.toString().substring(
      0,
      DiscoveryConstants.channelHashPrefixLength,
    );
  }
}
