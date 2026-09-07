import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/presentation/presentation.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_model.dart' show TunedChannel;
import 'package:keryx/core/state/radio_state_controller.dart';

import 'radio_host_provider.dart';
import 'talk_screen.dart';

/// TASK-048's Channels destination — default landing (UX-D01). Shows the
/// real currently-tuned channel and the real channel-recall memory the host
/// already tracks (`RadioHostSnapshot.channelMemory`); never a fabricated
/// contact/channel list (UX-FR-008/PRD §2.2, UX-D02: "No empty Contacts tab
/// in R1" — this is not that tab, and doesn't borrow its shape either).
///
/// Pushing Talk here uses this branch's own [Navigator] (see
/// `MobileAppShell`), so switching to Settings and back leaves Talk exactly
/// where it was — navigation alone never retunes or rebuilds the session
/// (UX-FR-005/007; VT-001).
class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  StreamSubscription<RadioHostSnapshot>? _hostSub;
  List<TunedChannel> _channelMemory = const <TunedChannel>[];

  @override
  void initState() {
    super.initState();
    final host = ref.read(radioHostProvider);
    _channelMemory = host.current.channelMemory;
    _hostSub = host.changes.listen((snapshot) {
      if (!mounted) return;
      setState(() => _channelMemory = snapshot.channelMemory);
    });
  }

  @override
  void dispose() {
    unawaited(_hostSub?.cancel());
    super.dispose();
  }

  void _tune(int channel, int privacyCode) {
    final host = ref.read(radioHostProvider);
    unawaited(RadioViewIntents(host).tune(channel, privacyCode));
  }

  void _openTalk(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TalkScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radioState = ref.watch(radioStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Channels')),
      body: ListView(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.radio),
            title: Text('Current: CH ${radioState.channel} · Code ${radioState.privacyCode}'),
            subtitle: Text(radioState.phase.cue.label),
            onTap: () => _openTalk(context),
            trailing: const Icon(Icons.chevron_right),
          ),
          if (_channelMemory.isNotEmpty) ...<Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Recently tuned'),
            ),
            for (final entry in _channelMemory)
              ListTile(
                leading: const Icon(Icons.history),
                title: Text('CH ${entry.channel} · Code ${entry.privacyCode}'),
                onTap: () {
                  _tune(entry.channel, entry.privacyCode);
                  _openTalk(context);
                },
              ),
          ],
        ],
      ),
    );
  }
}
