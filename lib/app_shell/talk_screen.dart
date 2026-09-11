import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'radio_host_provider.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';

/// Shell-composed Talk destination — mounts TASK-051's real [talkui.TalkScreen]
/// and supplies the navigation its header callbacks invoke.
///
/// TASK-068: this used to intercept the picker/stations header taps with
/// invisible 48×48 overlays positioned by hardcoded geometry matching Talk's
/// own header layout (`SafeArea` + 16/12 padding + 48 dp buttons), because
/// TASK-051's `TalkScreen` shipped no callback parameters. TASK-052's own
/// review proved that coupling was a live risk, not theoretical: shifting the
/// overlay's `top` by +100dp left every overlay-based test green while a
/// real-centre-tap probe went red. `TalkScreen` now exposes real
/// `onOpenPicker`/`onOpenStations`/`onOpenRadioControls` callbacks
/// (TASK-068), so this wrapper just wires them the normal way — no geometry,
/// no overlay, nothing that a future Talk layout change can silently break.
///
/// TASK-077 (ADR-002 §3 A1): Talk is now the shell's default tab, and
/// Stations is a sibling tab rather than a pushed screen, so the station
/// chip's tap switches tabs instead of pushing [ShellRoutes.openStations]
/// (which this task removes — nothing else called it). Radio controls moved
/// into the app bar's overflow menu, so `onOpenRadioControls` is omitted
/// entirely here — ADR-002 §3 A2: "rendered **only when non-null**".
///
/// Optional [host] keeps `const TalkScreen()` constructing (the TASK-048
/// stand-in signature); production always passes the app-scoped host.
class TalkScreen extends ConsumerWidget {
  const TalkScreen({super.key, this.host, required this.onSwitchToStations});

  final RadioHost? host;

  /// Invoked when the channel card's Stations affordance is tapped — the
  /// shell switches to the Stations tab (ADR-002 §3 A1) rather than pushing
  /// a screen.
  final VoidCallback onSwitchToStations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RadioHost resolved = host ?? ref.watch(radioHostProvider);

    return talkui.TalkScreen(
      key: ShellKeys.talk,
      host: resolved,
      onOpenPicker: () => ShellRoutes.openSelector(context, resolved),
      onOpenStations: onSwitchToStations,
    );
  }
}
