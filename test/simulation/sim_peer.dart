import 'dart:math';

import 'package:keryx/core/floor/floor.dart';
import 'package:keryx/core/identity/identity.dart';

import 'sim_network.dart';

/// One simulated radio in the TASK-023 soak harness: a real [FloorEngine]
/// (TASK-022, read-only import) wired to [SimNetwork], carrying enough
/// bookkeeping for the soak invariants to observe it. This file adds no
/// floor-control logic — only the harness plumbing driving TASK-022.
class SimPeer {
  SimPeer({
    required this.peerId,
    required SimNetwork network,
    required VirtualClock clock,
    required Duration tot,
  }) : engine = FloorEngine(
         localPeerId: peerId,
         transport: network.attach(peerId),
         clock: clock,
         tot: tot,
       ) {
    engine.effects.listen(effectLog.add);
  }

  final String peerId;
  final FloorEngine engine;
  final List<FloorEffect> effectLog = <FloorEffect>[];

  /// Set true once this peer has been made to "crash" (silently detached
  /// from the network mid-run, per the dossier's churn model) so the
  /// soak driver stops scheduling further PTT actions for it.
  bool crashed = false;

  void dispose() => engine.dispose();
}

/// Generates a fresh, stable, §8.6-shaped peerId for peer [n] of a soak
/// run from [random] — the SAME derivation TASK-009 uses in production
/// (`derivePeerId`, base32(SHA-256(installUuid))[:10]), read-only import,
/// so election behaviour in this harness matches the real ID space
/// ("uniformly distributed ID space that avoids election thrashing",
/// TS §8.6) rather than a harness-invented shortcut.
String simPeerId(Random random, int n) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final uuid =
      '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  return derivePeerId(uuid);
}
