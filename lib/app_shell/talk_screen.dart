import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/presentation/talk_target.dart' show PeerPresence;
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'directory_providers.dart';
import 'radio_host_provider.dart';
import 'shell_keys.dart';

/// Shell-composed Talk destination — mounts TASK-051/092's real
/// [talkui.TalkScreen] and supplies the v2 target/presence data and
/// navigation its header callbacks invoke.
///
/// v2 (TASK-093): the numbered-channel picker and the Stations tab are both
/// gone (Design §1/§5: "never channel, tune, station...") — `onOpenPicker`/
/// `onOpenStations` are simply omitted (ADR-002 §3 A2's "rendered only
/// when non-null" convention). `onSwitchToContacts`/`onSwitchToGroups`
/// back the no-target state's "Add your first contact"/"Create a group"
/// affordances (Design §2.1) by switching tabs, same pattern the v1 shell
/// used for its own tab switches.
///
/// Optional [host] keeps `const TalkScreen()` constructing (the TASK-048
/// stand-in signature); production always passes the app-scoped host.
class TalkScreen extends ConsumerWidget {
  const TalkScreen({
    super.key,
    this.host,
    required this.onSwitchToContacts,
    required this.onSwitchToGroups,
  });

  final RadioHost? host;
  final VoidCallback onSwitchToContacts;
  final VoidCallback onSwitchToGroups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RadioHost resolved = host ?? ref.watch(radioHostProvider);
    final target = ref.watch(currentTargetProvider)?.target;
    final presenceByPeerId = ref.watch(presenceByPeerIdProvider).valueOrNull ??
        const <String, PeerPresence>{};

    return talkui.TalkScreen(
      key: ShellKeys.talk,
      host: resolved,
      target: target,
      presenceByPeerId: presenceByPeerId,
      onAddContact: onSwitchToContacts,
      onCreateGroup: onSwitchToGroups,
    );
  }
}
