import 'package:flutter/material.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_export_screen.dart';
import 'package:keryx/features/event_qr_ui/event_qr_ui_scan_screen.dart';
import 'package:keryx/features/radio_controls/radio_controls_screen.dart';
import 'package:keryx/features/stations/stations_screen.dart';

import 'shell_keys.dart';

/// Pushes the Wave-4 screens this shell owns onto the caller's [Navigator].
///
/// Talk itself is pushed from [ChannelsScreen] (avoids an import cycle
/// with the Talk wrapper). Every destination here is a real TASK-050/053/
/// 054/056 widget, never a placeholder.
abstract final class ShellRoutes {
  static Future<void> openSelector(BuildContext context, RadioHost host) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => ChannelSelectorScreen(
          key: ShellKeys.channelSelector,
          host: host,
          onCancel: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  static Future<void> openStations(BuildContext context, RadioHost host) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => StationsScreen(
          key: ShellKeys.stations,
          onScan: () => openEventQrScan(routeContext, host),
          onExport: () => openEventQrExport(routeContext),
        ),
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
