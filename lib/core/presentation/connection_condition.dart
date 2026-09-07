import 'package:keryx/core/state/radio_state.dart' show RadioMode;

/// Configured preference vs. actually-effective route, kept as **separate**
/// fields (UX-FR-002: "configured mode and actual/effective connection
/// condition without conflating them"; Technical §7: "The UI must
/// distinguish configured preference from effective route. A configured
/// AUTO value does not establish that the app is currently connected to
/// both LAN and WAN.").
///
/// [configuredMode] mirrors `KeryxSettings.mode` verbatim — it may be
/// `RadioMode.auto`. [effectiveRoute] mirrors `RadioState.mode`, which
/// `RadioSessionController._resolveEffectiveMode` has already resolved to
/// a concrete `local`/`linked` choice before it ever reaches the reducer
/// (AUTO never appears there) — so this field is never `auto` in practice,
/// but that invariant belongs to the session controller, not this type;
/// this type does not itself assert it.
class ConnectionCondition {
  const ConnectionCondition({
    required this.configuredMode,
    required this.effectiveRoute,
    required this.degraded,
  });

  /// The user's own preference, exactly as stored (may be `auto`).
  final RadioMode configuredMode;

  /// The route actually in effect right now.
  final RadioMode effectiveRoute;

  /// True while the radio is in `RadioPhase.linkDegraded` /
  /// `RadioState.isNoLink` — connectivity is currently unavailable
  /// regardless of which route was configured or last effective (Design §4
  /// "No link" row).
  final bool degraded;

  @override
  bool operator ==(Object other) =>
      other is ConnectionCondition &&
      other.configuredMode == configuredMode &&
      other.effectiveRoute == effectiveRoute &&
      other.degraded == degraded;

  @override
  int get hashCode => Object.hash(configuredMode, effectiveRoute, degraded);

  @override
  String toString() =>
      'ConnectionCondition(configured: $configuredMode, '
      'effective: $effectiveRoute, degraded: $degraded)';
}
