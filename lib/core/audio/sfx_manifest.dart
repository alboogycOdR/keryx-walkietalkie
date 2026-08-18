import 'audio_mix.dart';
import 'sfx_id.dart';

/// Typed §7.1 registry: path, duration, loop points, loudness target.
final class SfxEntry {
  const SfxEntry({
    required this.id,
    required this.duration,
    this.loopStart = Duration.zero,
    this.loopEnd,
    this.targetLufs = AudioMix.sfxLufs,
  });

  final SfxId id;
  final Duration duration;
  final Duration loopStart;
  final Duration? loopEnd;
  final double targetLufs;

  String get assetPath => '${AudioMix.assetRoot}${id.assetStem}.wav';

  bool get loops => id.isLoopBed;

  Duration get resolvedLoopEnd => loopEnd ?? duration;

  bool get isLocalAsset => assetPath.startsWith(AudioMix.assetRoot);
}

/// Frozen placeholder durations matching `assets/sfx/tools/generate_placeholders.py`.
abstract final class SfxManifest {
  static const Map<SfxId, SfxEntry> entries = {
    SfxId.squelchOpen: SfxEntry(
      id: SfxId.squelchOpen,
      duration: Duration(milliseconds: 60),
    ),
    SfxId.squelchTail: SfxEntry(
      id: SfxId.squelchTail,
      duration: Duration(milliseconds: 70),
    ),
    SfxId.staticBed1: SfxEntry(
      id: SfxId.staticBed1,
      duration: Duration(milliseconds: 2000),
      loopEnd: Duration(milliseconds: 2000),
    ),
    SfxId.staticBed2: SfxEntry(
      id: SfxId.staticBed2,
      duration: Duration(milliseconds: 2000),
      loopEnd: Duration(milliseconds: 2000),
    ),
    SfxId.staticBed3: SfxEntry(
      id: SfxId.staticBed3,
      duration: Duration(milliseconds: 2000),
      loopEnd: Duration(milliseconds: 2000),
    ),
    SfxId.tuneBurst: SfxEntry(
      id: SfxId.tuneBurst,
      duration: Duration(milliseconds: 300),
    ),
    SfxId.scanTick: SfxEntry(
      id: SfxId.scanTick,
      duration: Duration(milliseconds: 25),
    ),
    SfxId.rogerK: SfxEntry(
      id: SfxId.rogerK,
      duration: Duration(milliseconds: 90),
    ),
    SfxId.rogerDual: SfxEntry(
      id: SfxId.rogerDual,
      duration: Duration(milliseconds: 180),
    ),
    SfxId.rogerMoto: SfxEntry(
      id: SfxId.rogerMoto,
      duration: Duration(milliseconds: 200),
    ),
    SfxId.denyBuzz: SfxEntry(
      id: SfxId.denyBuzz,
      duration: Duration(milliseconds: 200),
    ),
    SfxId.totWarn: SfxEntry(
      id: SfxId.totWarn,
      duration: Duration(milliseconds: 180),
    ),
    SfxId.totCut: SfxEntry(
      id: SfxId.totCut,
      duration: Duration(milliseconds: 250),
    ),
    SfxId.linkLost: SfxEntry(
      id: SfxId.linkLost,
      duration: Duration(milliseconds: 200),
    ),
    SfxId.linkUp: SfxEntry(
      id: SfxId.linkUp,
      duration: Duration(milliseconds: 160),
    ),
    SfxId.emgAlert: SfxEntry(
      id: SfxId.emgAlert,
      duration: Duration(milliseconds: 900),
      targetLufs: AudioMix.emergencyLufs,
    ),
    SfxId.rchkOk: SfxEntry(
      id: SfxId.rchkOk,
      duration: Duration(milliseconds: 120),
    ),
    SfxId.keyClick: SfxEntry(
      id: SfxId.keyClick,
      duration: Duration(milliseconds: 18),
    ),
    SfxId.knobTick: SfxEntry(
      id: SfxId.knobTick,
      duration: Duration(milliseconds: 8),
    ),
    SfxId.sliderThunk: SfxEntry(
      id: SfxId.sliderThunk,
      duration: Duration(milliseconds: 30),
    ),
    SfxId.powerOn: SfxEntry(
      id: SfxId.powerOn,
      duration: Duration(milliseconds: 280),
    ),
    SfxId.powerOff: SfxEntry(
      id: SfxId.powerOff,
      duration: Duration(milliseconds: 220),
    ),
  };

  static SfxEntry lookup(SfxId id) {
    final entry = entries[id];
    if (entry == null) {
      throw StateError('SfxId.$id missing from §7.1 manifest');
    }
    return entry;
  }

  static Iterable<SfxEntry> get all => SfxId.values.map(lookup);
}
