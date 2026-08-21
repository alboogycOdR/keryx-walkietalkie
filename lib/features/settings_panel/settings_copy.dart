import 'package:keryx/core/settings/settings_repository.dart';

/// DS §7 copy voice: "Plain, mechanical, unapologetic — an equipment
/// manual, not an app." Every string here is a noun/verb a radio user
/// already knows, never an apology, never a mood.
///
/// **On acceptance criterion 4's `MONITOR`/`MON`/*Monitor* example.** That
/// quote (DS §7 L128) is the spec's own illustration of the "same word
/// survives the whole flow" rule, not a requirement that a *Monitor*
/// control exist here — `KeryxSettings` (TASK-008/030, frozen, outside
/// this task's territory) has no `monitor` field, and `MONITOR`/`MON`
/// belong to the PTT key row (`lib/features/ptt/key_row.dart`), not the
/// back panel. The rule itself is honoured throughout below: every label
/// is the plain field identity (`SQUELCH`, `LATCH`, `BUSY LOCKOUT`,
/// `LOCAL ONLY`, `DIM`), the same word a spec reader or a future telltale
/// would use — none is a euphemism ("Listening sensitivity", "Auto-off")
/// for the thing it does.
abstract final class SettingsCopy {
  static const String screenTitle = 'BACK PANEL';
  static const String loadFailed =
      'Settings did not load. Close and reopen the back panel.';

  static const String audioSectionTitle = 'AUDIO';
  static const String squelchLabel = 'SQUELCH';
  static const String squelchDescription =
      'Sets the RX gate threshold and the resting hiss level.';
  static const String rogerLabel = 'ROGER BEEP';
  static const String rogerDescription =
      'End-of-transmission tone, played locally and sent in-band.';

  static const String txSectionTitle = 'TRANSMIT';
  static const String totLabel = 'TIME-OUT TIMER';
  static const String totDescription =
      'Maximum continuous transmit before a hard cut.';
  static const String latchLabel = 'LATCH';
  static const String latchDescription =
      'Double-tap to lock transmit, tap to release.';
  static const String lockoutLabel = 'BUSY LOCKOUT';
  static const String lockoutDescription =
      'Deny transmit while the floor is held.';

  static const String characterSectionTitle = 'CHARACTER';
  static const String dspLabel = 'CHARACTER DSP';
  static const String dspDescription =
      'Radio-character processing applied to receive audio.';

  /// DS FR-108 is not a ratified requirement (finding (mm) — absent from
  /// the Product Technical Spec; the UI spec files it under "Fold into
  /// KERYX v1.2"). Carried anyway per this task's own Description, which
  /// explicitly lists "dim mode" among the exposed settings, and disclosed
  /// here as a pinned implementation decision rather than silently built
  /// as if ratified.
  static const String dimLabel = 'DIM';
  static const String dimDescription =
      'Display and legend brightness follow ambient light, or set by hand.';

  static const String networkSectionTitle = 'NETWORK';
  static const String forceLocalLabel = 'LOCAL ONLY';
  static const String forceLocalDescription = 'Nothing leaves this network.';
  static const String regionLabel = 'REGION';
  static const String regionDescription =
      "Partitions numbered channels so CH 7 here isn't CH 7 elsewhere.";

  static String rogerOptionLabel(RogerBeepVariant value) => switch (value) {
    RogerBeepVariant.off => 'OFF',
    RogerBeepVariant.classic => 'CLASSIC',
    RogerBeepVariant.dualTone => 'DUAL-TONE',
    RogerBeepVariant.customPack => 'CUSTOM PACK',
  };

  static String dspOptionLabel(CharacterDspIntensity value) => switch (value) {
    CharacterDspIntensity.off => 'OFF',
    CharacterDspIntensity.light => 'LIGHT',
    CharacterDspIntensity.full => 'FULL',
  };

  static String dimOptionLabel(DimMode value) => switch (value) {
    DimMode.auto => 'AUTO',
    DimMode.manual => 'MANUAL',
  };
}
