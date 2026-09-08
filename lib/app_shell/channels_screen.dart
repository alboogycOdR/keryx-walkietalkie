import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/channels/channels_landing.dart';

import 'radio_host_provider.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';
import 'talk_screen.dart';

/// Channels destination — mounts TASK-049's [ChannelsLanding] as the
/// default landing (UX-D01). Open Talk and Select channel are callbacks
/// this composition root owns: Talk is TASK-051, the selector is TASK-050,
/// and neither lives under `lib/features/channels/**`.
class ChannelsScreen extends ConsumerWidget {
  const ChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ChannelsLanding(
      key: ShellKeys.channelsLanding,
      onOpenTalk: () => _openTalk(context, ref.read(radioHostProvider)),
      onSelectChannel: () =>
          ShellRoutes.openSelector(context, ref.read(radioHostProvider)),
    );
  }

  static Future<void> _openTalk(BuildContext context, RadioHost host) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TalkScreen(host: host),
      ),
    );
  }
}
