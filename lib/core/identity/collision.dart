/// One peer as seen on a channel, in join order.
typedef ChannelPeer = ({String peerId, String callsign});

/// Per-channel display names with numeric suffixes for later joiners
/// who share a callsign (TS §8.6 / FR-068).
///
/// First joiner with a given callsign keeps it (`BRAVO-7`). The next
/// renders `BRAVO-7 (2)`, then `(3)`, and so on. Collision is an exact
/// string match on the stored callsign — no case folding (generated
/// names are already uppercase).
///
/// This function does not consult [ChannelPeer.peerId] except as the
/// map key. It never rejects a duplicate callsign and never mutates
/// a peerId. Duplicate peerIds in [byJoinOrder] throw — the spec says
/// they cannot occur.
Map<String, String> displayNames(List<ChannelPeer> byJoinOrder) {
  final seenPeerIds = <String>{};
  final seenCallsigns = <String, int>{};
  final out = <String, String>{};

  for (final peer in byJoinOrder) {
    if (peer.peerId.isEmpty) {
      throw ArgumentError.value(peer.peerId, 'peerId', 'Must not be empty');
    }
    if (peer.callsign.isEmpty) {
      throw ArgumentError.value(peer.callsign, 'callsign', 'Must not be empty');
    }
    if (!seenPeerIds.add(peer.peerId)) {
      throw ArgumentError.value(
        peer.peerId,
        'peerId',
        'peerIds never collide; duplicate in join list',
      );
    }
    final prior = seenCallsigns[peer.callsign] ?? 0;
    seenCallsigns[peer.callsign] = prior + 1;
    out[peer.peerId] = prior == 0
        ? peer.callsign
        : '${peer.callsign} (${prior + 1})';
  }
  return out;
}
