/// User-facing copy for the successor Settings screen (Design §2.6 / §5).
///
/// Sentence case, plain language. The same field words the legacy back
/// panel used (Squelch, Latch, Local only, …) survive so a user who
/// learned the radio on the hatch still finds them.
abstract final class SettingsCopy {
  static const String title = 'Settings';
  static const String loadFailed = 'Settings did not load. Close and reopen Settings.';

  /// Matches `pubspec.yaml` `version:` — TASK-062 owns the release bump.
  static const String appVersion = '1.0.0+1';

  static const String radioSection = 'Radio';
  static const String radioSectionDescription =
      'Transmit limits and busy-lockout.';

  static const String audioSection = 'Audio';
  static const String audioSectionDescription =
      'Receive gate, end-of-TX tone, and character processing.';

  static const String connectivitySection = 'Connectivity';
  static const String connectivitySectionDescription =
      'How this radio reaches other people.';

  static const String identitySection = 'Identity';
  static const String identitySectionDescription =
      'The name other people see, and your KERYX ID.';

  static const String messagesSection = 'Messages';
  static const String messagesSectionDescription =
      'Voice messages arrive in v2.1. Retention applies from then.';

  static const String appearanceSection = 'Appearance';
  static const String appearanceSectionDescription =
      'Theme and display brightness. Does not reconnect the radio.';

  static const String aboutSection = 'About';
  static const String aboutSectionDescription = 'Version and sanitized status.';

  static const String totLabel = 'Time-out timer';
  static const String totDescription =
      'Maximum continuous transmit before a hard cut.';

  static const String latchLabel = 'Latch';
  static const String latchDescription =
      'Double-tap to lock transmit, tap to release.';

  static const String lockoutLabel = 'Busy lockout';
  static const String lockoutDescription = 'Deny transmit while the floor is held.';

  static const String squelchLabel = 'Squelch';
  static const String squelchDescription =
      'Sets the RX gate threshold and the resting hiss level.';

  static const String rogerLabel = 'Roger beep';
  static const String rogerDescription =
      'End-of-transmission tone, played locally and sent in-band.';

  static const String dspLabel = 'Character DSP';
  static const String dspDescription =
      'Radio-character processing applied to receive audio.';

  static const String audioRoutingLabel = 'Audio routing';
  static const String audioRoutingValue = 'Device default';
  static const String audioRoutingDescription =
      "Uses the phone's current output. End-of-TX and character sounds stay the radio pack.";

  static const String effectiveRouteLabel = 'Active path';
  static const String effectiveRouteDescription =
      'The path actually in use right now.';

  static const String forceLocalLabel = 'This network only';
  static const String forceLocalDescription = 'Nothing leaves this Wi-Fi network.';
  static const String forceLocalBlocksWan =
      'This-network-only is on. Contacts and presence will not work. Relay settings are stored but no internet call is made.';

  static const String relayUrlLabel = 'Relay URL';
  static const String relayUrlDescription =
      'Secure WebSocket relay. Leave blank when no relay is deployed.';
  static const String relayUrlError =
      'Relay URL must be a wss:// address with a host, or blank.';

  static const String tokenUrlLabel = 'Token URL';
  static const String tokenUrlDescription =
      'Advanced. Leave blank to use the relay token route.';
  static const String tokenUrlError =
      'Token URL must be an https:// address with a host, or blank.';

  static const String callsignLabel = 'Callsign';
  static const String callsignDescription =
      '2–12 letters, digits or hyphens. This is a display name, not an account.';
  static const String callsignInvalid =
      'Callsign must be 2–12 letters, digits or hyphens.';

  static const String showRecoveryPhraseLabel = 'Show recovery phrase';
  static const String showRecoveryPhraseDescription =
      'The 12 words that are the only way to get your KERYX ID back. Kept '
      'behind a confirmation and screenshots are blocked while shown.';
  static const String showRecoveryPhraseAction = 'Show';
  static const String showRecoveryPhraseUnavailable =
      'No recovery phrase was saved on this device (a restored identity '
      "keeps whichever phrase restored it — this device's copy isn't it).";
  static const String recoveryPhraseTitle = 'Your recovery phrase';
  static const String recoveryPhraseWarning =
      'Write these 12 words down and keep them safe. They are the only way '
      'to get your KERYX ID back.';
  static const String recoveryPhraseConfirmTitle = 'Show recovery phrase?';
  static const String recoveryPhraseConfirmBody =
      'Anyone who sees these 12 words can restore your KERYX ID on another '
      'device. Make sure nobody can see this screen.';
  static const String recoveryPhraseConfirmShow = 'Show';

  static const String restoreFromPhraseLabel = 'Restore from phrase';
  static const String restoreFromPhraseDescription =
      'Replaces this KERYX ID with one restored from a 12-word phrase.';
  static const String restoreFromPhraseAction = 'Restore';
  static const String restoreConfirmTitle = 'Replace this KERYX ID?';
  static const String restoreConfirmBody =
      'Restoring replaces the identity on this device. Contacts and groups '
      'made with the current ID stay with that ID, not the restored one.';
  static const String restoreConfirmContinue = 'Continue';
  static const String restoreDone =
      'Identity restored. Restart KERYX for the change to take full effect.';

  static const String preferDirectLabel = 'Prefer direct on Wi-Fi';
  static const String preferDirectDescription =
      'Use a local network path instead of the relay when both are '
      'available for the current room.';

  static const String messageRetentionLabel = 'Message retention';
  static const String messageRetentionDescription =
      'Local retention window before voice messages are purged. Used from '
      'v2.1.';
  static String messageRetentionValueLabel(int days) => '$days d';

  static const String themeLabel = 'Theme';
  static const String themeDescription =
      'Dark is the default. Light is complete. System follows the phone.';

  static const String dimLabel = 'Dim';
  static const String dimDescription =
      'Display and legend brightness follow ambient light, or set by hand.';

  static const String versionLabel = 'Version';
  static const String diagnosticsLabel = 'Status';
  static const String technicalDetailsLabel = 'Technical details';

  static const String reconnectsRadio = 'Reconnects radio';
  static const String confirmTitle = 'Reconnect the radio?';
  static const String confirmApply = 'Apply';
  static const String confirmCancel = 'Cancel';
  static const String confirmBody =
      'This setting rebuilds the radio session. If you are talking, the change waits until you stop transmitting so the microphone is never left open.';

  static const String deferredBanner =
      'Waiting until you stop transmitting before reconnecting.';
  static const String deferredCancel = 'Cancel waiting change';

  static const String microphoneOk = 'Microphone available';
  static const String microphoneRequired = 'Microphone required';
  static const String serviceOk = 'Background service available';
  static const String serviceUnavailable = 'Background service unavailable';
  static const String connectionOk = 'Connection ok';
  static const String connectionLost = 'Connection lost';
  static const String diagnosticsNone = 'None';

  static String rogerOptionLabel(String name) => switch (name) {
    'off' => 'Off',
    'classic' => 'Classic',
    'dualTone' => 'Dual-tone',
    'customPack' => 'Custom pack',
    _ => name,
  };

  static String dspOptionLabel(String name) => switch (name) {
    'off' => 'Off',
    'light' => 'Light',
    'full' => 'Full',
    _ => name,
  };

  static String dimOptionLabel(String name) => switch (name) {
    'auto' => 'Automatic',
    'manual' => 'Manual',
    _ => name,
  };

  static String transportOptionLabel(String name) => switch (name) {
    'none' => 'Connecting',
    'direct' => 'Direct',
    'relay' => 'Relay',
    'both' => 'Direct and relay',
    _ => name,
  };

  static String themeOptionLabel(String name) => switch (name) {
    'system' => 'System',
    'light' => 'Light',
    'dark' => 'Dark',
    _ => name,
  };

  static String totValueLabel(int seconds) => '${seconds}s';
}
