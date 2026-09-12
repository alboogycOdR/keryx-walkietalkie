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
  static const Key talk = Key('shell.talk');
  static const Key settings = Key('shell.settings');
  static const Key channelSelector = Key('shell.channel-selector');
  static const Key radioControls = Key('shell.radio-controls');
  static const Key eventQrScan = Key('shell.event-qr-scan');
  static const Key eventQrExport = Key('shell.event-qr-export');

  static const Key connectionIndicator = Key('shell.connection-indicator');
  static const Key overflowMenu = Key('shell.overflow-menu');
  static const Key overflowMyCode = Key('shell.overflow-my-code');
  static const Key overflowRadioControls = Key('shell.overflow-radio-controls');
  static const Key overflowSettings = Key('shell.overflow-settings');
  static const Key tabTalk = Key('shell.tab-talk');
  static const Key tabContacts = Key('shell.tab-contacts');
  static const Key tabGroups = Key('shell.tab-groups');

  // v2 (TASK-093): Contacts/Groups tab bodies and the routes they push.
  static const Key contactsTab = Key('shell.contacts-tab');
  static const Key groupsTab = Key('shell.groups-tab');
  static const Key groupDetail = Key('shell.group-detail');
  static const Key groupInvite = Key('shell.group-invite');
  static const Key newGroup = Key('shell.new-group');
  static const Key joinWithCode = Key('shell.join-with-code');
  static const Key myCode = Key('shell.my-code');
  static const Key onboarding = Key('shell.onboarding');
  static const Key onboardingChooser = Key('shell.onboarding-chooser');
  static const Key onboardingRestore = Key('shell.onboarding-restore');
  static const Key restore = Key('shell.restore');
  static const Key recoveryPhraseView = Key('shell.recovery-phrase-view');
}
