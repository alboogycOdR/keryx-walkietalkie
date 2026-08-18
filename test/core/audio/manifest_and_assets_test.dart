import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';

import 'wav_lufs.dart';

void main() {
  test('manifest covers every SfxId exactly once', () {
    expect(SfxManifest.entries.keys.toSet(), SfxId.values.toSet());
    expect(SfxManifest.entries.length, SfxId.values.length);
  });

  test('every §7.1 asset is a local 48 kHz 16-bit mono WAV', () {
    for (final entry in SfxManifest.all) {
      expect(entry.isLocalAsset, isTrue, reason: entry.assetPath);
      final file = File(entry.assetPath);
      expect(file.existsSync(), isTrue, reason: 'missing ${entry.assetPath}');
      final wav = WavFile.read(file);
      expect(wav.sampleRate, AudioMix.sampleRateHz, reason: entry.id.name);
      expect(wav.bitsPerSample, AudioMix.bitDepth, reason: entry.id.name);
      expect(wav.channels, AudioMix.channels, reason: entry.id.name);
      expect(
        wav.duration.inMilliseconds,
        closeTo(entry.duration.inMilliseconds, 1),
        reason: '${entry.id.name} duration',
      );
    }
  });

  test('SFX assets are −16 LUFS; emergency is −12 LUFS', () {
    for (final entry in SfxManifest.all) {
      final wav = WavFile.read(File(entry.assetPath));
      final lufs = integratedLufs(wav.samples);
      final tolerance = entry.duration.inMilliseconds < 50 ? 2.5 : 1.25;
      expect(
        lufs,
        closeTo(entry.targetLufs, tolerance),
        reason: '${entry.id.assetStem} measured $lufs LUFS, '
            'target ${entry.targetLufs}',
      );
    }
  });

  test('static beds have wrap-around continuity at the loop point', () {
    for (final id in BedGains.beds) {
      final wav = WavFile.read(File(SfxManifest.lookup(id).assetPath));
      final first = wav.samples.first;
      final last = wav.samples.last;
      expect(
        (first - last).abs(),
        lessThan(0.08),
        reason: '${id.assetStem} loop discontinuity',
      );
    }
  });

  test('knob tick is the 8 ms sample; squelch cracks sit in 40–80 ms', () {
    expect(
      SfxManifest.lookup(SfxId.knobTick).duration,
      const Duration(milliseconds: 8),
    );
    for (final id in [SfxId.squelchOpen, SfxId.squelchTail]) {
      final ms = SfxManifest.lookup(id).duration.inMilliseconds;
      expect(ms, inInclusiveRange(40, 80));
    }
    expect(
      SfxManifest.lookup(SfxId.scanTick).duration.inMilliseconds,
      lessThanOrEqualTo(30),
    );
  });
}
