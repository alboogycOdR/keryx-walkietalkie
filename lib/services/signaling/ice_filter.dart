/// LAN-only ICE filter (TS §8.3 step 2: host candidates; mDNS ICE).
///
/// Allowed: `typ host`, and candidates whose address is an mDNS `.local`
/// hostname. Rejected: `typ srflx`, `typ relay`, `typ prflx`. Unknown
/// shapes (no `typ`, no `.local`) are rejected so a STUN/TURN trickle
/// cannot sneak through.
bool isLanIceCandidate(String candidate) {
  final lower = candidate.toLowerCase();
  if (lower.contains('typ srflx') ||
      lower.contains('typ relay') ||
      lower.contains('typ prflx')) {
    return false;
  }
  if (lower.contains('typ host')) return true;
  if (_mdnsHost.hasMatch(lower)) return true;
  return false;
}

final _mdnsHost = RegExp(r'(?:^|[\s])[\w.-]+\.local(?:[\s]|$)');

final _sdpCandidateLine = RegExp(r'^a=candidate:.*$', multiLine: true);

/// Drop non-LAN `a=candidate:` lines from an SDP blob. Other lines pass
/// through unchanged so TASK-021's session description stays intact.
String sanitizeSdp(String sdp) {
  return sdp.replaceAllMapped(_sdpCandidateLine, (match) {
    final line = match[0]!;
    final candidate = line.startsWith('a=candidate:')
        ? line.substring('a='.length)
        : line;
    return isLanIceCandidate(candidate) ? line : '';
  });
}
