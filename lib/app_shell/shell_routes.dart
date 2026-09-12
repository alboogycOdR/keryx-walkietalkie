import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioState;
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_scan_screen.dart';
import 'package:keryx/features/my_code/my_code_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/settings/settings_screen.dart';

import 'directory_providers.dart';
import 'shell_keys.dart';

/// Pushes the Wave-4/R2 screens this shell owns onto the caller's
/// [Navigator]. Talk, Channels and Stations are the shell's tab roots
/// (ADR-002 §2 O2/§3 A1) — Selector, Radio controls, Settings and Event QR
/// are the full-screen routes pushed from them or from the app bar's
/// overflow menu.
abstract final class ShellRoutes {
  /// Pushes the channel selector / direct-tune flow (TASK-050).
  ///
  /// [onApplied] is invoked, and the route auto-popped, the moment
  /// `RadioState`'s channel/privacy-code pair actually changes while this
  /// route is on top — the real, host-confirmed signal that a tune request
  /// this screen submitted has taken effect, never a synthesized one
  /// (Technical §3/§6: never fabricate success). Used by the Channels tab so
  /// a successful apply returns straight to Talk (ADR-002 §3 A1: "Channels
  /// recall success and selector apply switch to Talk"). `null` (the
  /// default, used when opened from the Talk tab itself) preserves the
  /// pre-R2 behaviour: the screen stays open until Cancel/back.
  static Future<void> openSelector(
    BuildContext context,
    RadioHost host, {
    VoidCallback? onApplied,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => onApplied == null
            ? ChannelSelectorScreen(
                key: ShellKeys.channelSelector,
                host: host,
                onCancel: () => Navigator.of(routeContext).pop(),
              )
            : _AutoReturnSelector(host: host, onApplied: onApplied),
      ),
    );
  }

  static Future<void> openRadioControls(BuildContext context, RadioHost host) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RadioControlsScreen(
          key: ShellKeys.radioControls,
          host: host,
        ),
      ),
    );
  }

  /// Pushes Settings full-screen with back (ADR-002 §3 A1: moved out of the
  /// persistent shell into the app bar's overflow menu).
  static Future<void> openSettings(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(key: ShellKeys.settings),
      ),
    );
  }

  /// Pushes My code (Design §2.4) full-screen from the ⋮ menu, above Radio
  /// controls and Settings (Design §1). Reads the real identity via
  /// [identityProvider] — a still-loading/absent key pair renders nothing
  /// rather than pushing a broken screen (a fresh install's identity is
  /// created synchronously by [radioHostProvider]'s own boot, so this is
  /// only ever hit in the sub-second window before that completes).
  static Future<void> openMyCode(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => Consumer(
          builder: (context, WidgetRef ref, _) {
            final identityAsync = ref.watch(identityProvider);
            final identity = identityAsync.valueOrNull;
            final publicKey = identity?.keyPair?.publicKey;
            if (identity == null || publicKey == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return MyCodeScreen(
              key: ShellKeys.myCode,
              callsign: identity.callsign.value,
              publicKey: publicKey,
            );
          },
        ),
      ),
    );
  }

  static Future<void> openEventQrScan(BuildContext context, RadioHost host) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EventQrUiScanScreen(
          key: ShellKeys.eventQrScan,
          host: host,
        ),
      ),
    );
  }

  static Future<void> openEventQrExport(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const EventQrUiExportScreen(
          key: ShellKeys.eventQrExport,
        ),
      ),
    );
  }
}

/// Wraps [ChannelSelectorScreen] with a shell-owned "return to Talk on
/// success" behaviour that the selector screen itself doesn't implement
/// (it has no `Navigator` of its own — Cancel is the caller's `onCancel`,
/// and there is no equivalent "on apply" callback; `Owned_Paths` for this
/// task does not include `channel_selector_screen.dart`, so this wrapper is
/// the correct seam rather than adding one there).
///
/// The only trustworthy "the requested tune actually happened" signal
/// available from outside the selector is `RadioState`'s own
/// channel/privacy-code pair changing — that field is the single source of
/// truth every other screen already reads as "the current channel"
/// (Technical §3), and it only moves when the host has genuinely retuned.
/// Watching it (rather than re-deriving the selector's own outcome stream,
/// which is private to that screen) means this wrapper cannot be fooled by
/// e.g. the user merely typing into the direct-entry fields.
class _AutoReturnSelector extends ConsumerStatefulWidget {
  const _AutoReturnSelector({required this.host, required this.onApplied});

  final RadioHost host;
  final VoidCallback onApplied;

  @override
  ConsumerState<_AutoReturnSelector> createState() =>
      _AutoReturnSelectorState();
}

class _AutoReturnSelectorState extends ConsumerState<_AutoReturnSelector> {
  late final int _initialChannel;
  late final int _initialCode;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    final RadioState state = ref.read(radioStateProvider);
    _initialChannel = state.channel;
    _initialCode = state.privacyCode;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<RadioState>(radioStateProvider, (previous, next) {
      if (_handled) return;
      if (next.channel != _initialChannel || next.privacyCode != _initialCode) {
        _handled = true;
        widget.onApplied();
        Navigator.of(context).pop();
      }
    });

    return ChannelSelectorScreen(
      key: ShellKeys.channelSelector,
      host: widget.host,
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}
