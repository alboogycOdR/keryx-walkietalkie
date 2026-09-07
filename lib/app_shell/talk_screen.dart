import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state_controller.dart';

import 'radio_host_provider.dart';

/// TASK-048's thin stand-in Talk destination (Design §1: "Talk is a
/// dedicated route or nested channel destination, but its presentation
/// lifecycle must not own the radio session").
///
/// This screen owns nothing: it reads the single app-scoped [RadioHost]
/// via [radioHostProvider] and the presentation projection TASK-046 built
/// on top of it, and forwards every gesture through [RadioViewIntents] —
/// it never constructs a session, floor engine, audio pipeline or service
/// controller of its own, and pushing/popping this route never calls a
/// host lifecycle method (VT-001). The full skeuomorphic Talk UI is Wave
/// 4's job (TASK-050/051); this is deliberately minimal so the shell is
/// testable without duplicating that work or shipping fake data.
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key});

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen> {
  // Latch is UI-owned (Technical §4) — TASK-048/050 are explicitly on the
  // hook (TASK-046's Review_Findings) for actually tracking it, since
  // `RadioViewState.project` takes it as a caller-supplied argument rather
  // than sourcing it from the host.
  bool _latched = false;

  StreamSubscription<RadioHostSnapshot>? _hostSub;
  RadioHostSnapshot _snapshot = const RadioHostSnapshot();

  @override
  void initState() {
    super.initState();
    final host = ref.read(radioHostProvider);
    _snapshot = host.current;
    // Mirrors the host's own side state (mic/service condition, stations,
    // channel memory) into this route's rebuild — never a second source of
    // truth for `RadioState` itself, which stays on `radioStateProvider`
    // via `ref.watch` in `build` (Technical §3).
    _hostSub = host.changes.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    });
  }

  @override
  void dispose() {
    unawaited(_hostSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(radioHostProvider);
    final intents = RadioViewIntents(host);
    final radioState = ref.watch(radioStateProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull;

    if (settings == null) {
      // Settings still loading/erroring — nothing fake to show yet.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final viewState = RadioViewState.project(
      radioState: radioState,
      hostSnapshot: _snapshot,
      settings: settings,
      latched: _latched,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Talk')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('CH ${viewState.channel} · Code ${viewState.privacyCode}'),
            const SizedBox(height: 8),
            Text(viewState.phase.cue.label),
            for (final cue in viewState.activeOverlayCues) Text(cue.label),
            const Spacer(),
            Center(
              child: GestureDetector(
                onTapDown: (_) => intents.press(),
                onTapUp: (_) {
                  if (_latched) return;
                  intents.release();
                },
                onTapCancel: () {
                  if (_latched) return;
                  intents.release();
                },
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent,
                  ),
                  child: const Center(
                    child: Text(
                      'PTT',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  final next = !_latched;
                  setState(() => _latched = next);
                  if (!next) intents.releaseLatch();
                },
                child: Text(_latched ? 'Unlatch' : 'Latch'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
