import 'package:flutter/foundation.dart';

/// Widget keys for the composed Wave-4/R2 destinations this shell mounts.
///
/// Tests address screens by these keys rather than by placeholder copy
/// TASK-048's stand-ins used.
///
/// TASK-068: the Talk header's picker/stations/radio-controls affordances
/// used to need shell-owned hit-target keys here because they were invisible
/// overlays composed by the shell, not real buttons on `TalkScreen`. Now
/// that `TalkScreen` (`lib/features/talk/talk_screen.dart`) exposes real
/// callbacks, those buttons are addressed by their own keys
/// (`keryx-talk-picker`/`keryx-talk-stations`/`keryx-talk-radio-controls`)
/// the same way every other `TalkScreen` control already is — there is
/// nothing shell-owned left to key here.
///
/// TASK-077: adds keys for the R2 top app bar / icon tab strip (ADR-002
/// §2 O2, §3 A1) — the connection indicator dot and the three tab buttons,
/// so tests can address them without depending on icon `Icon` matching or
/// unstable tooltip text lookups.
abstract final class ShellKeys {
  static const Key channelsLanding = Key('shell.channels-landing');
  static const Key talk = Key('shell.talk');
  static const Key settings = Key('shell.settings');
  static const Key channelSelector = Key('shell.channel-selector');
  static const Key stations = Key('shell.stations');
  static const Key radioControls = Key('shell.radio-controls');
  static const Key eventQrScan = Key('shell.event-qr-scan');
  static const Key eventQrExport = Key('shell.event-qr-export');

  static const Key connectionIndicator = Key('shell.connection-indicator');
  static const Key overflowMenu = Key('shell.overflow-menu');
  static const Key overflowRadioControls = Key('shell.overflow-radio-controls');
  static const Key overflowSettings = Key('shell.overflow-settings');
  static const Key tabTalk = Key('shell.tab-talk');
  static const Key tabChannels = Key('shell.tab-channels');
  static const Key tabStations = Key('shell.tab-stations');
}
