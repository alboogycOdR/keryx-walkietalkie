import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';

void main() {
  const sr = 48000.0;

  group('RadioCharacterChain', () {
    test('default intensity is Light', () {
      final chain = RadioCharacterChain();
      expect(chain.intensity, CharacterIntensity.light);
      expect(chain.makeupDb, 3.0);
      expect(chain.makeupDb, inInclusiveRange(AudioMix.makeupMinDb, AudioMix.makeupMaxDb));
    });

    test('Off is a sample-exact bypass', () {
      final chain = RadioCharacterChain(intensity: CharacterIntensity.off);
      final input = _sine(hz: 1000, seconds: 0.05, amplitude: 0.4);
      // Poison filter state first with a different signal, then flip to Off.
      chain.intensity = CharacterIntensity.full;
      chain.process(_sine(hz: 200, seconds: 0.02, amplitude: 0.8));
      chain.intensity = CharacterIntensity.off;
      final out = chain.process(input);
      expect(out.length, input.length);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], input[i], reason: 'sample $i');
      }
    });

    test('Full attenuates 50 Hz and 12 kHz versus 1 kHz', () {
      final inBand = _settledRms(
        RadioCharacterChain(intensity: CharacterIntensity.full),
        _sine(hz: 1000, seconds: 0.25, amplitude: 0.5),
      );
      final low = _settledRms(
        RadioCharacterChain(intensity: CharacterIntensity.full),
        _sine(hz: 50, seconds: 0.25, amplitude: 0.5),
      );
      final high = _settledRms(
        RadioCharacterChain(intensity: CharacterIntensity.full),
        _sine(hz: 12000, seconds: 0.25, amplitude: 0.5),
      );
      expect(inBand, greaterThan(0.05));
      expect(inBand / low, greaterThan(4), reason: 'HP @ 300 Hz should crush 50 Hz');
      expect(inBand / high, greaterThan(4), reason: 'LP @ 3400 Hz should crush 12 kHz');
    });

    test('300–3400 Hz biquad pair attenuates the band edges', () {
      final hp = Biquad.highPass(sampleRateHz: sr, cutoffHz: AudioMix.characterHpHz);
      final lp = Biquad.lowPass(sampleRateHz: sr, cutoffHz: AudioMix.characterLpHz);

      double settled(Float32List input) {
        final buf = Float32List.fromList(input);
        hp.reset();
        lp.reset();
        hp.processInPlace(buf);
        lp.processInPlace(buf);
        return RxGate.rmsOf(Float32List.sublistView(buf, buf.length * 2 ~/ 3));
      }

      final mid = settled(_sine(hz: 1000, seconds: 0.25, amplitude: 0.5));
      final low = settled(_sine(hz: 50, seconds: 0.25, amplitude: 0.5));
      final high = settled(_sine(hz: 12000, seconds: 0.25, amplitude: 0.5));
      expect(mid / low, greaterThan(8));
      expect(mid / high, greaterThan(8));
    });

    test('3:1 compression shrinks a step-level contrast', () {
      const loudAmp = 0.8;
      const quietAmp = 0.25;
      final loud = _settledRms(
        RadioCharacterChain(intensity: CharacterIntensity.full),
        _sine(hz: 1000, seconds: 0.3, amplitude: loudAmp),
      );
      final quiet = _settledRms(
        RadioCharacterChain(intensity: CharacterIntensity.full),
        _sine(hz: 1000, seconds: 0.3, amplitude: quietAmp),
      );
      final inRatio = loudAmp / quietAmp;
      final outRatio = loud / quiet;
      expect(outRatio, lessThan(inRatio * 0.7));
      expect(outRatio, greaterThan(1.2));
    });

    test('makeup stays inside +0…+6 dB', () {
      for (final intensity in CharacterIntensity.values) {
        final chain = RadioCharacterChain(intensity: intensity);
        expect(
          chain.makeupDb,
          inInclusiveRange(AudioMix.makeupMinDb, AudioMix.makeupMaxDb),
          reason: intensity.name,
        );
      }
    });

    test('hiss floor mixes at the supplied squelch level and is silent at 0', () {
      final silent = RadioCharacterChain(
        intensity: CharacterIntensity.full,
        hissSeed: 1,
      )..hissLevel = 0;
      final withHiss = RadioCharacterChain(
        intensity: CharacterIntensity.full,
        hissSeed: 1,
      )..hissLevel = 0.12;
      final zeros = Float32List(sr ~/ 10);
      expect(silent.process(zeros).every((s) => s == 0), isTrue);
      final mixed = withHiss.process(Float32List(sr ~/ 10));
      expect(RxGate.rmsOf(mixed), greaterThan(0.001));
    });

    test('rejects non-finite samples', () {
      final chain = RadioCharacterChain();
      expect(
        () => chain.process(Float32List.fromList([0, double.nan])),
        throwsArgumentError,
      );
    });
  });

  group('SoftKneeCompressor', () {
    test('ratio is 3:1', () {
      expect(SoftKneeCompressor(sampleRateHz: sr).ratio, AudioMix.compressorRatio);
    });
  });
}

Float32List _sine({
  required double hz,
  required double seconds,
  required double amplitude,
  double sampleRate = 48000,
}) {
  final n = (sampleRate * seconds).round();
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amplitude * math.sin(2 * math.pi * hz * i / sampleRate);
  }
  return out;
}

double _settledRms(RadioCharacterChain chain, Float32List input) {
  final out = chain.process(input);
  final start = out.length * 2 ~/ 3;
  return RxGate.rmsOf(Float32List.sublistView(out, start));
}
