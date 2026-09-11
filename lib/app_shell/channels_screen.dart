import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/features/channels/channels_landing.dart';

import 'radio_host_provider.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';

/// Channels tab body (ADR-002 §2 O2, §3 A1) — mounts TASK-049's
/// [ChannelsLanding] `embedded` beneath the shell's own top app bar and tab
/// strip. Talk is a persistent sibling tab now, not a screen this pushes
/// (`onOpenTalk` is omitted — TASK-051 is a separate destination), so this
/// screen only owns the selector launch and the "switch to Talk" signal a
/// successful tune (recall, or a selector opened from here) produces.
class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key, required this.onSwitchToTalk});

  /// Invoked once after a recent-channel recall retunes successfully, and
  /// after a selector opened from this tab applies successfully (ADR-002
  /// §3 A1: "Channels recall success and selector apply switch to Talk").
  final VoidCallback onSwitchToTalk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChannelsLanding(
      key: ShellKeys.channelsLanding,
      embedded: true,
      onTuneSucceeded: onSwitchToTalk,
      onSelectChannel: () => ShellRoutes.openSelector(
        context,
        ref.read(radioHostProvider),
        onApplied: onSwitchToTalk,
      ),
    );
  }
}
