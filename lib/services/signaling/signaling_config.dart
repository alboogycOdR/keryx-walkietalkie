import 'signaling_constants.dart';

/// Local identity for a signaling session. Never includes raw channel/code.
class SignalingConfig {
  const SignalingConfig({
    required this.peerId,
    required this.callsign,
    required this.channelHashPrefix,
    this.protocolVersion = SignalingConstants.envelopeVersion,
  });

  /// §8.6 peerId. Used as the hello `from` and for the dial-dedup rule.
  final String peerId;

  /// Display callsign, carried on hello and PRESENCE `cs`.
  final String callsign;

  /// Same prefix discovery advertised as TXT `ch`. Handshake mismatch closes.
  final String channelHashPrefix;

  /// Envelope `v`. v1 is `1`.
  final int protocolVersion;

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
        'looks like a raw region|ch|code tuple; pass the discovery prefix',
      );
    }
    if (protocolVersion < 1) {
      throw ArgumentError.value(protocolVersion, 'protocolVersion');
    }
  }
}
