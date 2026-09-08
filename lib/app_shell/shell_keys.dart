import 'package:flutter/foundation.dart';

/// Widget keys for the composed Wave-4 destinations this shell mounts.
///
/// Tests (and the overlay hit-targets on Talk) address screens by these
/// keys rather than by placeholder copy TASK-048's stand-ins used.
abstract final class ShellKeys {
  static const Key channelsLanding = Key('shell.channels-landing');
  static const Key talk = Key('shell.talk');
  static const Key settings = Key('shell.settings');
  static const Key channelSelector = Key('shell.channel-selector');
  static const Key stations = Key('shell.stations');
  static const Key radioControls = Key('shell.radio-controls');
  static const Key eventQrScan = Key('shell.event-qr-scan');
  static const Key eventQrExport = Key('shell.event-qr-export');

  /// Invisible 48×48 overlay over Talk's channel-picker IconButton
  /// (`keryx-talk-picker`). Talk's own `onPressed` is a no-op (TASK-051
  /// left it for the composition root and shipped no callback).
  static const Key talkPickerHit = Key('shell.talk-picker-hit');

  /// Invisible 48×48 overlay over Talk's stations IconButton
  /// (`keryx-talk-stations`). Same TASK-051 no-op as [talkPickerHit].
  static const Key talkStationsHit = Key('shell.talk-stations-hit');

  /// Visible shell-owned affordance for TASK-054. Talk has no Radio
  /// Controls button at all (not even a no-op), and this task cannot
  /// edit `lib/features/talk/**`.
  static const Key talkRadioControls = Key('shell.talk-radio-controls');
}
