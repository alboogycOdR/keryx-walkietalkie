import 'dart:typed_data';

import 'audio_mix.dart';
import 'dsp/biquad.dart';
import 'dsp/compressor.dart';
import 'dsp/hiss_floor.dart';

/// Character DSP intensity (TS §7.2). Default is [light].
enum CharacterIntensity { off, light, full }

/// Voice-bus radio character: 300–3400 Hz band-pass, 3:1 soft-knee, makeup,
/// optional hiss mixed at the supplied squelch-knob level.
///
/// Pure buffer-in / buffer-out. No network, no I/O.
final class RadioCharacterChain {
  RadioCharacterChain({
    CharacterIntensity intensity = CharacterIntensity.light,
    double sampleRateHz = 48000,
    int hissSeed = 0x4B455258,
  })  : _intensity = intensity,
        _sampleRateHz = sampleRateHz,
        _hp = Biquad.highPass(
          sampleRateHz: sampleRateHz,
          cutoffHz: AudioMix.characterHpHz,
        ),
        _lp = Biquad.lowPass(
          sampleRateHz: sampleRateHz,
          cutoffHz: AudioMix.characterLpHz,
        ),
        _compressor = SoftKneeCompressor(
          sampleRateHz: sampleRateHz,
          ratio: AudioMix.compressorRatio,
          makeupDb: _makeupFor(intensity),
          kneeDb: _kneeFor(intensity),
        ),
        _hiss = HissFloor(sampleRateHz: sampleRateHz, seed: hissSeed);

  CharacterIntensity _intensity;
  final double _sampleRateHz;
  final Biquad _hp;
  final Biquad _lp;
  final SoftKneeCompressor _compressor;
  final HissFloor _hiss;

  /// Mix coefficient for the optional hiss floor (squelch-mapped, ≥ 0).
  double hissLevel = 0;

  CharacterIntensity get intensity => _intensity;

  set intensity(CharacterIntensity value) {
    if (value == _intensity) {
      return;
    }
    _intensity = value;
    _compressor.makeupDb = _makeupFor(value);
    _compressor.kneeDb = _kneeFor(value);
    reset();
  }

  double get makeupDb => _compressor.makeupDb;

  double get sampleRateHz => _sampleRateHz;

  /// Process [input] into a new buffer. [off] is a sample-exact bypass.
  Float32List process(Float32List input) {
    _validate(input);
    if (_intensity == CharacterIntensity.off) {
      return Float32List.fromList(input);
    }
    final out = Float32List.fromList(input);
    _hp.processInPlace(out);
    _lp.processInPlace(out);
    _compressor.processInPlace(out);
    if (hissLevel > 0) {
      _hiss.mixInto(out, hissLevel * _hissScaleFor(_intensity));
    }
    return out;
  }

  void reset() {
    _hp.reset();
    _lp.reset();
    _compressor.reset();
    _hiss.reset();
  }

  static double _makeupFor(CharacterIntensity intensity) {
    return switch (intensity) {
      CharacterIntensity.off => AudioMix.makeupMinDb,
      CharacterIntensity.light => 3.0,
      CharacterIntensity.full => AudioMix.makeupMaxDb,
    };
  }

  static double _kneeFor(CharacterIntensity intensity) {
    return switch (intensity) {
      CharacterIntensity.off => 12.0,
      CharacterIntensity.light => 8.0,
      CharacterIntensity.full => 4.0,
    };
  }

  static double _hissScaleFor(CharacterIntensity intensity) {
    return switch (intensity) {
      CharacterIntensity.off => 0.0,
      CharacterIntensity.light => 0.5,
      CharacterIntensity.full => 1.0,
    };
  }

  static void _validate(Float32List input) {
    for (var i = 0; i < input.length; i++) {
      if (!input[i].isFinite) {
        throw ArgumentError.value(input[i], 'input[$i]', 'must be finite');
      }
    }
  }
}
