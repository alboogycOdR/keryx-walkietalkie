import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/state/radio_state.dart';

import 'sim_peer.dart';

/// Records the running set of peers who currently believe (from their own
/// [FloorEngine.effects]) that they hold the transmit floor, and fails
/// loudly the instant more than one does — KRX-044's core safety
/// invariant ("zero double-grants"), checked at every state transition
/// rather than sampled after the fact, so it genuinely covers "at no
/// simulated instant do two peers believe they hold the floor".
///
/// [InvariantViolation] carries the run's seed so a failure reproduces
/// exactly (KRX-044: "Seeds logged so failures reproduce").
class SafetyMonitor {
  SafetyMonitor(this.seed);

  final int seed;
  final Set<String> _believesHolding = <String>{};

  /// peerId -> the [DateTime] its lease was granted, for lease-expiry
  /// bound checks (invariant c).
  final Map<String, DateTime> grantedAt = <String, DateTime>{};

  void attach(SimPeer peer, VirtualClock clock) {
    peer.engine.effects.listen((effect) {
      if (effect is! DispatchRadio) return;
      final event = effect.event;
      if (event is TransmitGranted) {
        _believesHolding.add(peer.peerId);
        grantedAt[peer.peerId] = clock.now();
        if (_believesHolding.length > 1) {
          throw InvariantViolation(
            seed,
            'double-grant: ${_believesHolding.toList()..sort()} all believe '
            'they hold the floor at ${clock.now()}',
          );
        }
      } else if (event is EndTransmit) {
        _believesHolding.remove(peer.peerId);
      }
    });
  }

  Set<String> get currentHolders => Set<String>.unmodifiable(_believesHolding);

  /// Stop counting [peerId] toward the double-grant check — call this the
  /// instant a peer stops existing (silent crash, or graceful leave/
  /// dispose), never on a normal `EndTransmit`. A crashed radio's screen
  /// freezing on "TX" is not a double-grant: nobody else can observe it,
  /// and a *live* peer later being granted the floor after that peer's
  /// lease naturally expires is the invariant working, not breaking.
  /// Without this, every crash-while-holding run would misfire this
  /// monitor the next time anyone else gets granted.
  void forget(String peerId) => _believesHolding.remove(peerId);
}

/// Thrown by [SafetyMonitor] (or an explicit `expect`) on an invariant
/// breach. Always carries the seed of the run that broke it.
class InvariantViolation implements Exception {
  InvariantViolation(this.seed, this.message);

  final int seed;
  final String message;

  @override
  String toString() => 'InvariantViolation(seed=$seed): $message';
}
