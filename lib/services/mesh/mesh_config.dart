/// Mesh audio codec + transport configuration (KRX-032, TS §8.1 codec row,
/// §8.3 step 2).
abstract final class MeshConfig {
  /// "Opus, mono, 16–24 kbps, 20 ms frames, in-band FEC on, DTX off during
  /// TX" — TS §8.1 codec row.
  static const int minBitrateBps = 16000;
  static const int maxBitrateBps = 24000;
  static const int ptimeMs = 20;
  static const bool inBandFecOn = true;
  static const bool dtxOffDuringTx = true;
  static const int channels = 1;

  /// TS §8.3 step 2: "LAN candidates only (host candidates; mDNS ICE)" — no
  /// STUN/TURN servers configured on LOCAL. An empty ICE server list plus
  /// [iceTransportPolicyAll] restricts gathering to host candidates only,
  /// since there is nothing else to gather.
  static const List<Map<String, dynamic>> iceServers = <Map<String, dynamic>>[];

  /// getUserMedia audio constraints — APM on per §8.1 (AEC/NS/AGC).
  static const Map<String, dynamic> audioConstraints = <String, dynamic>{
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    'channelCount': channels,
  };

  /// Data-channel label for the floor-control transport (TS §8.3 step 4).
  static const String floorDataChannelLabel = 'floor';
}
