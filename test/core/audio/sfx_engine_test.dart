import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';

void main() {
  late RecordingAudioSink sink;
  late _Clock clock;
  late SfxEngine engine;

  setUp(() {
    sink = RecordingAudioSink();
    clock = _Clock();
    engine = SfxEngine(sink: sink, now: clock.now);
  });

  tearDown(() {
    engine.dispose();
  });

  test('every one-shot plays on the SFX bus from a local asset', () {
    for (final id in SfxId.values.where((id) => !id.isLoopBed)) {
      engine.play(id);
    }
    expect(sink.oneShots, isNotEmpty);
    for (final event in sink.oneShots) {
      expect(event.bus, AudioBus.sfx);
      expect(event.assetPath, startsWith(AudioMix.assetRoot));
      expect(event.assetPath, endsWith('.wav'));
      expect(engine.busFor(event.id), AudioBus.sfx);
    }
    expect(sink.oneShots.any((e) => e.bus == AudioBus.voice), isFalse);
  });

  test('SFX engine never writes a voice-bus play event', () {
    engine.play(SfxId.tuneBurst);
    engine.setBedLevel(0.5);
    engine.playRoger(RogerVariant.classicK);
    expect(
      [
        ...sink.oneShots.map((e) => e.bus),
        ...sink.loops.map((e) => e.bus),
      ],
      everyElement(AudioBus.sfx),
    );
  });

  test('roger off is silent; other variants map to manifest ids', () {
    engine.playRoger(RogerVariant.off);
    expect(sink.oneShots, isEmpty);

    engine.playRoger(RogerVariant.classicK);
    engine.playRoger(RogerVariant.dualTone);
    engine.playRoger(RogerVariant.moto);
    expect(sink.oneShots.map((e) => e.id), [
      SfxId.rogerK,
      SfxId.rogerDual,
      SfxId.rogerMoto,
    ]);
  });

  test('loop beds cannot be played as one-shots', () {
    expect(() => engine.play(SfxId.staticBed1), throwsArgumentError);
  });

  test('setBedLevel starts three SFX-bus loops then updates gains', () {
    engine.setBedLevel(0);
    expect(sink.loops.map((e) => e.id), BedGains.beds);
    expect(sink.loops.every((e) => e.bus == AudioBus.sfx), isTrue);
    expect(sink.loops.every((e) => e.loopStart == Duration.zero), isTrue);
    expect(
      sink.loops.every((e) => e.loopEnd == const Duration(milliseconds: 2000)),
      isTrue,
    );
    expect(sink.loopGains[SfxId.staticBed1], 0);
    expect(sink.loopGains[SfxId.staticBed3], 0);

    engine.setBedLevel(1);
    expect(sink.loopGains[SfxId.staticBed1], closeTo(0, 1e-12));
    expect(sink.loopGains[SfxId.staticBed2], closeTo(0, 1e-12));
    expect(sink.loopGains[SfxId.staticBed3], closeTo(1, 1e-12));
    expect(sink.loops, hasLength(3));
  });

  test('programme SFX ducks voice −3 dB for at most 150 ms', () {
    engine.play(SfxId.tuneBurst);
    expect(engine.isVoiceDucked, isTrue);
    expect(engine.voiceGainDb, AudioMix.sfxDuckVoiceDb);
    expect(
      sink.events.whereType<SetBusGainEvent>().last,
      isA<SetBusGainEvent>()
          .having((e) => e.bus, 'bus', AudioBus.voice)
          .having((e) => e.gainDb, 'gainDb', AudioMix.sfxDuckVoiceDb),
    );

    clock.advance(const Duration(milliseconds: 149));
    engine.tick();
    expect(engine.isVoiceDucked, isTrue);

    clock.advance(const Duration(milliseconds: 1));
    engine.tick();
    expect(engine.isVoiceDucked, isFalse);
    expect(engine.voiceGainDb, 0);
    expect(
      sink.events.whereType<SetBusGainEvent>().last.gainDb,
      0,
    );
  });

  test('short SFX duck window matches duration, not the 150 ms cap', () {
    engine.play(SfxId.squelchOpen); // 60 ms
    clock.advance(const Duration(milliseconds: 59));
    engine.tick();
    expect(engine.isVoiceDucked, isTrue);
    clock.advance(const Duration(milliseconds: 1));
    engine.tick();
    expect(engine.isVoiceDucked, isFalse);
  });

  test('cosmetic SFX never duck the voice bus', () {
    for (final id in SfxId.values.where((id) => id.isCosmetic)) {
      engine.play(id);
    }
    expect(engine.isVoiceDucked, isFalse);
    expect(sink.events.whereType<SetBusGainEvent>(), isEmpty);
  });

  test('voice never ducks the SFX bus', () {
    engine.play(SfxId.denyBuzz);
    expect(
      sink.events.whereType<SetBusGainEvent>().map((e) => e.bus),
      everyElement(AudioBus.voice),
    );
    expect(sink.busGainsDb[AudioBus.sfx], 0);
  });

  test('beds do not duck voice', () {
    engine.setBedLevel(0.8);
    expect(engine.isVoiceDucked, isFalse);
    expect(sink.events.whereType<SetBusGainEvent>(), isEmpty);
  });

  test('dispose stops everything and restores voice gain', () {
    engine.setBedLevel(0.4);
    engine.play(SfxId.emgAlert);
    engine.dispose();
    expect(sink.events.whereType<StopAllEvent>(), isNotEmpty);
    expect(sink.busGainsDb[AudioBus.voice], 0);
    expect(() => engine.play(SfxId.powerOn), throwsStateError);
  });
}

final class _Clock {
  DateTime _now = DateTime.utc(2026, 1, 1);

  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
}
