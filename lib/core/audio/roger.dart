import 'sfx_id.dart';

/// FR-062 roger-beep variants (custom pack is a later asset drop).
enum RogerVariant {
  off,
  classicK,
  dualTone,
  moto,
}

extension RogerVariantPlayback on RogerVariant {
  SfxId? get sfxId => switch (this) {
        RogerVariant.off => null,
        RogerVariant.classicK => SfxId.rogerK,
        RogerVariant.dualTone => SfxId.rogerDual,
        RogerVariant.moto => SfxId.rogerMoto,
      };
}
