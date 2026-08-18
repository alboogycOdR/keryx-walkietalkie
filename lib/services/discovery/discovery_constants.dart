/// Wire constants for LOCAL discovery (FR-041, TS §8.1 / §8.3).
abstract final class DiscoveryConstants {
  /// NSD / mDNS service type. Native Android registers `_keryx._tcp.`
  /// (trailing dot required by [NsdManager]); this is the spec form.
  static const String serviceType = '_keryx._tcp';

  /// Floor / discovery protocol version advertised in TXT `v`.
  static const int protocolVersion = 1;

  /// TXT keys. Spec: `cs`, `ch`, `v`. Extra `p` is the TASK-020 signaling port.
  static const String txtCallsign = 'cs';
  static const String txtChannelHash = 'ch';
  static const String txtVersion = 'v';
  static const String txtPort = 'p';

  /// UDP broadcast fallback (TS §8.3 step 5): 2 s interval for 30 s after tune.
  static const Duration beaconInterval = Duration(seconds: 2);
  static const Duration beaconWindow = Duration(seconds: 30);

  /// Well-known LAN beacon port. Not a channel/code; carries only hashed `ch`.
  static const int beaconPort = 48721;

  /// Hex length of the privacy prefix placed in TXT `ch`.
  static const int channelHashPrefixLength = 8;

  static const String methodChannel = 'za.co.basileia.keryx/nsd';
  static const String eventChannel = 'za.co.basileia.keryx/nsd_events';

  static const String methodStart = 'start';
  static const String methodStop = 'stop';
}
