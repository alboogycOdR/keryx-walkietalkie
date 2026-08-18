import 'sfx_id.dart';

/// Squelch-knob crossfade across the three static beds (TS §7.1).
///
/// [level] 0 = silent (squelch closed). 1 = [SfxId.staticBed3] at unity.
/// Intermediate values linearly crossfade silence → bed1 → bed2 → bed3.
final class BedGains {
  const BedGains({
    required this.bed1,
    required this.bed2,
    required this.bed3,
  });

  final double bed1;
  final double bed2;
  final double bed3;

  double operator [](SfxId id) {
    switch (id) {
      case SfxId.staticBed1:
        return bed1;
      case SfxId.staticBed2:
        return bed2;
      case SfxId.staticBed3:
        return bed3;
      default:
        throw ArgumentError.value(id, 'id', 'not a static bed');
    }
  }

  static const beds = <SfxId>[
    SfxId.staticBed1,
    SfxId.staticBed2,
    SfxId.staticBed3,
  ];
}

abstract final class BedMixer {
  /// Maps a closed-unit squelch level onto the three bed gains.
  static BedGains gainsFor(double level) {
    if (level.isNaN) {
      throw ArgumentError.value(level, 'level', 'must be a finite 0..1');
    }
    if (level < 0.0 || level > 1.0) {
      throw ArgumentError.value(level, 'level', 'must be in 0..1');
    }
    if (level == 0.0) {
      return const BedGains(bed1: 0, bed2: 0, bed3: 0);
    }
    if (level == 1.0) {
      return const BedGains(bed1: 0, bed2: 0, bed3: 1);
    }
    const third = 1.0 / 3.0;
    if (level <= third) {
      return BedGains(bed1: level / third, bed2: 0, bed3: 0);
    }
    if (level <= 2 * third) {
      final t = (level - third) / third;
      return BedGains(bed1: 1.0 - t, bed2: t, bed3: 0);
    }
    final t = (level - 2 * third) / third;
    return BedGains(bed1: 0, bed2: 1.0 - t, bed3: t);
  }
}
