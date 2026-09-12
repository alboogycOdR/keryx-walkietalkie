import 'package:keryx/core/state/radio_state.dart' show Transport;

/// Live transport vs. degraded connectivity (Technical §6.3).
///
/// [transport] is the session's actual path (`none` until a v2 target is
/// selected). [routeLabel] is never a v1 LOCAL/LINKED/AUTO word.
class ConnectionCondition {
  const ConnectionCondition({
    required this.transport,
    required this.degraded,
  });

  /// Transports currently carrying audio for the selected room.
  final Transport transport;

  /// Whether a concrete transport has been selected.
  bool get isResolved => transport != Transport.none;

  /// User-facing path text. Unresolved stays `Connecting`.
  String get routeLabel => switch (transport) {
    Transport.none => 'Connecting',
    Transport.direct => 'Direct',
    Transport.relay => 'Relay',
    Transport.both => 'Direct and relay',
  };

  /// True while the radio is in `RadioPhase.linkDegraded` /
  /// `RadioState.isNoLink`.
  final bool degraded;

  @override
  bool operator ==(Object other) =>
      other is ConnectionCondition &&
      other.transport == transport &&
      other.degraded == degraded;

  @override
  int get hashCode => Object.hash(transport, degraded);

  @override
  String toString() =>
      'ConnectionCondition(transport: $transport, '
      'resolved: $isResolved, degraded: $degraded)';
}
