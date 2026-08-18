/// Locked mixer constants from TS §7 / §7.2.
abstract final class AudioMix {
  static const int sampleRateHz = 48000;
  static const int bitDepth = 16;
  static const int channels = 1;

  /// SFX loudness target (TS §7 preamble).
  static const double sfxLufs = -16.0;

  /// Emergency tone loudness target (TS §7 preamble).
  static const double emergencyLufs = -12.0;

  /// SFX ducks voice by this amount during overlap (TS §7.2).
  static const double sfxDuckVoiceDb = -3.0;

  /// Duck window is capped at 150 ms (TS §7.2).
  static const Duration maxDuck = Duration(milliseconds: 150);

  static const String assetRoot = 'assets/sfx/v1/';
}
