import 'package:keryx/core/floor/floor.dart' show FloorEngine;
import 'package:keryx/core/radio_host/radio_host.dart' show RadioHostSnapshot;
import 'package:keryx/core/settings/settings_repository.dart' show KeryxSettings;
import 'package:keryx/core/state/radio_state.dart'
    show RadioPhase, RadioState;

/// Session-affecting subset — **must stay aligned** with
/// `KeryxRadioHost._sessionAffectingFieldsChanged`
/// (`lib/core/radio_host/keryx_radio_host.dart`).
///
/// That method is private in frozen territory, so this file mirrors it.
/// A drift here would either reconnect on a presentation-only toggle
/// (VT-003 fail) or skip a real rebuild (stale session).
bool sessionAffectingFieldsChanged(KeryxSettings a, KeryxSettings b) =>
    a.mode != b.mode ||
    a.forceLocalOnly != b.forceLocalOnly ||
    a.relayUrl != b.relayUrl ||
    a.tokenServiceUrl != b.tokenServiceUrl ||
    a.totSeconds != b.totSeconds ||
    a.busyLockout != b.busyLockout ||
    a.region != b.region;

/// Fields whose apply rebuilds the communication session.
const Set<String> sessionAffectingFieldNames = <String>{
  'mode',
  'forceLocalOnly',
  'relayUrl',
  'tokenServiceUrl',
  'totSeconds',
  'busyLockout',
  'region',
};

/// Whether applying settings now would tear down a live TX.
///
/// Authoritative source is [FloorEngine.isTransmitting] when the host
/// snapshot carries an engine (Technical §3: the engine is TX-ownership
/// truth). When the snapshot has no engine (boot, or a test double),
/// [RadioPhase.tx] is the fallback — that is the reducer's own TX phase,
/// not a UI flag.
bool isLocallyTransmitting({
  required RadioHostSnapshot snapshot,
  required RadioState radio,
}) {
  final FloorEngine? engine = snapshot.floorEngine;
  if (engine != null) {
    return engine.isTransmitting;
  }
  return radio.phase == RadioPhase.tx;
}

/// Relay URL: empty (unconfigured) or `wss://` with a host. Matches
/// `KeryxSettings._asEndpoint` without writing a reduced object on a
/// typo — invalid input is refused in the UI instead of clamped.
bool isValidRelayUrl(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return true;
  }
  final Uri? uri = Uri.tryParse(trimmed);
  return uri != null && uri.host.isNotEmpty && uri.scheme == 'wss';
}

/// Token URL: empty (derive from relay) or `https://` with a host.
bool isValidTokenUrl(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return true;
  }
  final Uri? uri = Uri.tryParse(trimmed);
  return uri != null && uri.host.isNotEmpty && uri.scheme == 'https';
}
