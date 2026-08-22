import 'package:keryx/core/state/radio_state.dart';

/// A remote station currently visible on the tuned channel, projected for
/// UI consumption (roster list / station panel).
///
/// [signalQuality] is a **disclosed placeholder** (TASK-035): LOCAL
/// discovery/signaling and the LINKED relay do not yet report a per-peer
/// signal metric — that is KRX-035's telemetry job, out of this task's
/// scope. Until KRX-035 lands, every [StationInfo] is stamped with
/// [placeholderSignalQuality], the maximum of [RadioState]'s 1–9 S-meter
/// domain. Pinning "full bars" rather than "no bars" is deliberate: a
/// silently-wrong "weak signal" reading would be a false negative a user
/// might act on (e.g. assume a station is about to drop), whereas "full
/// bars" for an unmeasured peer is a neutral placeholder nobody will read
/// as a real distress signal. Replace this with a live value the moment
/// KRX-035 exists; do not build UI logic that depends on the placeholder
/// value itself.
class StationInfo {
  const StationInfo({
    required this.peerId,
    required this.callsign,
    this.signalQuality = placeholderSignalQuality,
  });

  /// TASK-035 disclosed decision — see class dartdoc.
  static const int placeholderSignalQuality = RadioState.maximumSignalQuality;

  final String peerId;
  final String callsign;
  final int signalQuality;

  @override
  bool operator ==(Object other) =>
      other is StationInfo &&
      other.peerId == peerId &&
      other.callsign == callsign &&
      other.signalQuality == signalQuality;

  @override
  int get hashCode => Object.hash(peerId, callsign, signalQuality);

  @override
  String toString() =>
      'StationInfo($peerId cs=$callsign signalQuality=$signalQuality)';
}
