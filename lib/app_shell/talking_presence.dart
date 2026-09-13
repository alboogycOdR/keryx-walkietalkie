/// TASK-106 send side (Technical §4.3, Design §4): pushes `talking`
/// true/false over the presence socket whenever local TX starts/ends, so a
/// contact who is idle can be auto-joined into this device's room by
/// `incoming_call.dart` on the *other* end.
///
/// Mirrors `presence_bootstrap.dart`'s shape exactly: a plain
/// `Provider<void>`, read once (never watched) at shell composition, that
/// owns exactly one `ref.listen` subscription for the container's
/// lifetime. It does not start presence itself (that is
/// `presence_bootstrap.dart`'s job) and does not touch `currentTargetProvider`
/// or `radioHostProvider` (that is `incoming_call.dart`'s, the *receive*
/// side) — this file is the outbound half only.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioPhase, RadioState;
import 'package:keryx/core/state/radio_state_controller.dart';

import 'directory_providers.dart';

/// Watches `radioStateProvider.phase` and calls
/// `PresenceClient.setTalking(true/false)` (via `presenceClientProvider`)
/// exactly on the boundary crossings into/out of [RadioPhase.tx] — not on
/// every rebuild while transmitting, and not for any other phase
/// transition (Design §4: only actual TX, never `txRequest`/`rxActive`,
/// drives the wire signal a peer auto-joins on).
final talkingPresenceProvider = Provider<void>((ref) {
  bool? lastTalking;

  Future<void> maybeSend(RadioState state) async {
    final talking = state.phase == RadioPhase.tx;
    if (talking == lastTalking) return;
    lastTalking = talking;
    final presence = await ref.read(presenceClientProvider.future);
    presence?.setTalking(talking);
  }

  ref.listen<RadioState>(
    radioStateProvider,
    (previous, next) => unawaited(maybeSend(next)),
    fireImmediately: true,
  );
});
