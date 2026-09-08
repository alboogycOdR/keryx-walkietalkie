import 'package:keryx/core/identity/identity.dart' show Callsign, isPeerId;
import 'package:keryx/services/session/session.dart' show StationInfo;

import 'station_copy.dart';

/// Display name for a roster row (UX-FR-026).
///
/// A known callsign is shown only when it is a real callsign, not when it
/// is empty, identical to the peer ID, or itself a peer-ID encoding.
/// Peer IDs are never returned — the caller renders
/// [StationsCopy.unknownStation] instead.
String stationDisplayName(StationInfo station) {
  final String raw = station.callsign.trim();
  if (raw.isEmpty) {
    return StationsCopy.unknownStation;
  }
  if (raw == station.peerId) {
    return StationsCopy.unknownStation;
  }
  if (isPeerId(raw)) {
    return StationsCopy.unknownStation;
  }
  if (!Callsign.pattern.hasMatch(raw)) {
    return StationsCopy.unknownStation;
  }
  return raw;
}
