import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/stations/stations_screen.dart' as stationsui;

import 'radio_host_provider.dart';
import 'shell_keys.dart';
import 'shell_routes.dart';

/// Stations tab body (ADR-002 §2 O2, §3 A1) — mounts TASK-053's
/// [stationsui.StationsScreen] `embedded` beneath the shell's own top app
/// bar and tab strip, wiring the Event QR scan/export affordances to the
/// full-screen routes this composition root owns.
class StationsScreen extends ConsumerWidget {
  const StationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RadioHost host = ref.watch(radioHostProvider);
    return stationsui.StationsScreen(
      key: ShellKeys.stations,
      embedded: true,
      onScan: () => ShellRoutes.openEventQrScan(context, host),
      onExport: () => ShellRoutes.openEventQrExport(context),
    );
  }
}
