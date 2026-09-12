import 'package:keryx/core/state/radio_state.dart' show RadioMode, Transport;

/// Configured preference vs. actually-effective route, kept as **separate**
/// fields (UX-FR-002: "configured mode and actual/effective connection
/// condition without conflating them"; Technical §7: "The UI must
/// distinguish configured preference from effective route. A configured
/// AUTO value does not establish that the app is currently connected to
/// both LAN and WAN.").
///
/// [configuredMode] mirrors `KeryxSettings.mode` verbatim — it may be
/// `RadioMode.auto`. [isResolved] distinguishes an unresolved route from a
/// concrete `local`/`linked` route, so a caller can label the former as
/// connecting rather than presenting AUTO as an active connection.
class ConnectionCondition {
  const ConnectionCondition({
    required this.configuredMode,
    required this.effectiveRoute,
    required this.degraded,
  });

  /// The user's own preference, exactly as stored (may be `auto`).
  final RadioMode configuredMode;

  /// The last route reported by radio state. Read [routeLabel] rather than
  /// this value when presenting it to a user, because it is AUTO while the
  /// session is still unresolved.
  final RadioMode effectiveRoute;

  /// Whether a concrete effective route has been selected.
  bool get isResolved => effectiveRoute != RadioMode.auto;

  /// User-facing effective-route text. This is deliberately never `AUTO`:
  /// AUTO is a configured preference, not a connected route.
  String get routeLabel =>
      isResolved ? effectiveRoute.name.toUpperCase() : 'Connecting';

  /// v2 (Technical §6.3/§7, TASK-088 re-scope note §6a): derived, additive
  /// projection of [effectiveRoute] onto the v2 `Transport` vocabulary —
  /// `local` -> `direct`, `linked` -> `relay`, unresolved (`auto`) ->
  /// `none`. This is a stopgap: it can never report [Transport.both],
  /// because the v1 [effectiveRoute] this reads from is a single value.
  /// TASK-093 (Technical §10 item 9) switches callers over to reading
  /// `RadioState.transport` directly once `RadioSessionController`
  /// populates it for a real v2 session; until then this getter keeps
  /// every v2-shaped consumer compiling against a v1 session unmodified.
  Transport get transport => switch (effectiveRoute) {
    RadioMode.local => Transport.direct,
    RadioMode.linked => Transport.relay,
    RadioMode.auto => Transport.none,
  };

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
      'effective: $effectiveRoute, resolved: $isResolved, degraded: $degraded)';
}
