import 'discovered_peer.dart';

/// Snapshot of LOCAL discovery. `lanTrouble` is the `LAN?` display flag.
class DiscoveryState {
  const DiscoveryState({
    required this.radioOn,
    required this.multicastLockHeld,
    required this.nsdActive,
    required this.nsdFailed,
    required this.beaconActive,
    required this.beaconWindowElapsed,
    required this.heardAnyDiscoveryTraffic,
    required this.lanTrouble,
    required this.peers,
  });

  static const idle = DiscoveryState(
    radioOn: false,
    multicastLockHeld: false,
    nsdActive: false,
    nsdFailed: false,
    beaconActive: false,
    beaconWindowElapsed: false,
    heardAnyDiscoveryTraffic: false,
    lanTrouble: false,
    peers: [],
  );

  /// Radio / LOCAL discovery session is running (`start` without `stop`).
  final bool radioOn;

  /// Native MulticastLock is held. True only while discovery is active.
  final bool multicastLockHeld;

  /// NSD register + browse both reported success.
  final bool nsdActive;

  /// NSD register or browse reported a hard failure.
  final bool nsdFailed;

  /// UDP fallback window is currently transmitting.
  final bool beaconActive;

  /// The 30 s post-tune window has finished (or never started).
  final bool beaconWindowElapsed;

  /// Any valid `_keryx._tcp` resolve or Keryx beacon was heard (any channel).
  /// Distinguishes an empty channel from a filtered LAN.
  final bool heardAnyDiscoveryTraffic;

  /// True when both NSD and the UDP window failed to prove the LAN is open.
  /// Consumer maps this to the `LAN?` flag (TS §8.3 step 5). No dialog.
  final bool lanTrouble;

  /// Matching-channel peers currently known (NSD + UDP, last writer wins).
  final List<DiscoveredPeer> peers;

  DiscoveryState copyWith({
    bool? radioOn,
    bool? multicastLockHeld,
    bool? nsdActive,
    bool? nsdFailed,
    bool? beaconActive,
    bool? beaconWindowElapsed,
    bool? heardAnyDiscoveryTraffic,
    bool? lanTrouble,
    List<DiscoveredPeer>? peers,
  }) {
    return DiscoveryState(
      radioOn: radioOn ?? this.radioOn,
      multicastLockHeld: multicastLockHeld ?? this.multicastLockHeld,
      nsdActive: nsdActive ?? this.nsdActive,
      nsdFailed: nsdFailed ?? this.nsdFailed,
      beaconActive: beaconActive ?? this.beaconActive,
      beaconWindowElapsed: beaconWindowElapsed ?? this.beaconWindowElapsed,
      heardAnyDiscoveryTraffic:
          heardAnyDiscoveryTraffic ?? this.heardAnyDiscoveryTraffic,
      lanTrouble: lanTrouble ?? this.lanTrouble,
      peers: peers ?? this.peers,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DiscoveryState &&
        other.radioOn == radioOn &&
        other.multicastLockHeld == multicastLockHeld &&
        other.nsdActive == nsdActive &&
        other.nsdFailed == nsdFailed &&
        other.beaconActive == beaconActive &&
        other.beaconWindowElapsed == beaconWindowElapsed &&
        other.heardAnyDiscoveryTraffic == heardAnyDiscoveryTraffic &&
        other.lanTrouble == lanTrouble &&
        _listEq(other.peers, peers);
  }

  @override
  int get hashCode => Object.hash(
    radioOn,
    multicastLockHeld,
    nsdActive,
    nsdFailed,
    beaconActive,
    beaconWindowElapsed,
    heardAnyDiscoveryTraffic,
    lanTrouble,
    Object.hashAll(peers),
  );
}

bool _listEq(List<DiscoveredPeer> a, List<DiscoveredPeer> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
