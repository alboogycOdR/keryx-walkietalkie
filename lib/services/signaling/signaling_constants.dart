/// Locked constants for LOCAL signaling (KRX-031 / KRX-034).
abstract final class SignalingConstants {
  /// Envelope version. Unknown versions are ignored.
  static const int envelopeVersion = 1;

  /// Supported remote-session envelope (TS §8.3 step 3). Soft: warn beyond.
  static const int lanPeerSoftCap = 16;
}
