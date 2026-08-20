import 'package:flutter/foundation.dart';

/// One entry in the STN-tap station-list flip panel (FR-067).
///
/// This is a display-layer value type owned by the face-assembly task. It is
/// deliberately NOT sourced from `RadioState` (the reducer carries only an
/// aggregate `stationCount`/`signalQuality`, per TS §8.2's single-source
/// invariant) — a real roster with per-station callsign + link quality
/// requires the presence/telemetry feed that TASK-020 (`lib/services/signaling/**`)
/// owns, and TASK-020 is still `TBD` as of this task. Until it lands, the
/// face wires an empty `List<StationInfo>` by default (see `FaceScreen`) so
/// the flip panel renders an honest "no other stations" list rather than
/// synthesizing fake peers. Widget tests inject non-empty lists directly.
@immutable
class StationInfo {
  const StationInfo({
    required this.peerId,
    required this.callsign,
    required this.signalQuality,
  }) : assert(peerId != ''),
       assert(callsign != ''),
       assert(signalQuality >= 1 && signalQuality <= 9);

  final String peerId;
  final String callsign;

  /// S-meter reading for this station, S1-S9 per FR-069/§8.9.
  final int signalQuality;

  @override
  bool operator ==(Object other) =>
      other is StationInfo &&
      peerId == other.peerId &&
      callsign == other.callsign &&
      signalQuality == other.signalQuality;

  @override
  int get hashCode => Object.hash(peerId, callsign, signalQuality);
}

/// Pure projection behind FR-069's status-strip aggregate rule: "while a
/// station transmits it shows that station's link; at idle it shows the
/// worst active peer link."
///
/// Returns `null` when [stations] is empty (nothing to aggregate — the
/// status strip renders its own "no signal" treatment in that case).
int? aggregateSignalQuality({
  required List<StationInfo> stations,
  required String? activeSpeakerPeerId,
}) {
  if (stations.isEmpty) return null;
  if (activeSpeakerPeerId != null) {
    for (final station in stations) {
      if (station.peerId == activeSpeakerPeerId) return station.signalQuality;
    }
  }
  var worst = stations.first.signalQuality;
  for (final station in stations.skip(1)) {
    if (station.signalQuality < worst) worst = station.signalQuality;
  }
  return worst;
}
