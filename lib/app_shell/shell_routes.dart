import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/my_code/my_code_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/settings/settings_screen.dart';

import 'directory_providers.dart';
import 'shell_keys.dart';

/// Pushes the full-screen routes this shell owns onto the caller's
/// [Navigator]. Talk, Contacts and Groups are the shell's tab roots
/// (Design §1). Radio controls, Settings and My code are the full-screen
/// routes pushed from the app bar's overflow menu.
abstract final class ShellRoutes {
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
  /// [identityProvider] — a still-loading/absent key pair renders a
  /// spinner rather than pushing a broken screen.
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
}
