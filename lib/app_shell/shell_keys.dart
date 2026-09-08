import 'package:flutter/foundation.dart';

/// Widget keys for the composed Wave-4 destinations this shell mounts.
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
abstract final class ShellKeys {
  static const Key channelsLanding = Key('shell.channels-landing');
  static const Key talk = Key('shell.talk');
  static const Key settings = Key('shell.settings');
  static const Key channelSelector = Key('shell.channel-selector');
  static const Key stations = Key('shell.stations');
  static const Key radioControls = Key('shell.radio-controls');
  static const Key eventQrScan = Key('shell.event-qr-scan');
  static const Key eventQrExport = Key('shell.event-qr-export');
}
