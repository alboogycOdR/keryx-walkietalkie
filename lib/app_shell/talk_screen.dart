import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'radio_host_provider.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';

/// Shell-composed Talk destination — mounts TASK-051's real [talkui.TalkScreen]
/// and supplies the navigation the screen's header buttons do not.
///
/// TASK-051's picker (`keryx-talk-picker`) and stations (`keryx-talk-stations`)
/// `IconButton`s ship with empty `onPressed` bodies and no callback
/// parameters; Design §1 still places Channel selector, Stations and Radio
/// controls under Talk. This wrapper intercepts those two header hits with
/// invisible 48×48 overlays aligned to Talk's own header geometry
/// (`SafeArea` + 16/12 padding + 48 dp buttons) and adds a visible Radio
/// Controls affordance (Talk has no third header button to overlay).
///
/// Optional [host] keeps `const TalkScreen()` constructing (the TASK-048
/// stand-in signature); production always passes the app-scoped host.
class TalkScreen extends ConsumerWidget {
  const TalkScreen({super.key, this.host});

  final RadioHost? host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RadioHost resolved = host ?? ref.watch(radioHostProvider);
    final Color iconColor = KeryxUxTokens.of(context).textPrimary;

    return Stack(
      children: <Widget>[
        talkui.TalkScreen(key: ShellKeys.talk, host: resolved),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 16,
          right: 16,
          height: 48,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 48),
              const Expanded(child: SizedBox.shrink()),
              _HeaderHitTarget(
                key: ShellKeys.talkPickerHit,
                onTap: () => ShellRoutes.openSelector(context, resolved),
              ),
              _HeaderHitTarget(
                key: ShellKeys.talkStationsHit,
                onTap: () => ShellRoutes.openStations(context, resolved),
              ),
            ],
          ),
        ),
        Positioned(
          left: 4,
          bottom: 4,
          child: Material(
            type: MaterialType.transparency,
            child: IconButton(
              key: ShellKeys.talkRadioControls,
              tooltip: 'Radio controls',
              onPressed: () =>
                  ShellRoutes.openRadioControls(context, resolved),
              icon: Icon(Icons.tune, color: iconColor),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opaque 48×48 hit target matching Talk's header IconButton size
/// (Design §2.2 48 dp minimum). Sits above the real button so the
/// shell, not the empty `onPressed`, receives the tap.
class _HeaderHitTarget extends StatelessWidget {
  const _HeaderHitTarget({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(width: 48, height: 48),
    );
  }
}
