import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';

void main() {
  group('Squelch mapping', () {
    test('detent 0 is silent bed and the highest gate threshold', () {
      expect(Squelch.bedLevelFromDetent(0), 0);
      expect(
        Squelch.gateThresholdFromDetent(0),
        greaterThan(Squelch.gateThresholdFromDetent(10)),
      );
    });

    test('detent 10 is a faint bed, never full unity', () {
      expect(Squelch.bedLevelFromDetent(10), Squelch.maxRestingBed);
      expect(Squelch.maxRestingBed, lessThan(1 / 3));
      expect(Squelch.maxRestingBed, greaterThan(0));
    });

    test('bed level is monotonic increasing; gate threshold decreasing', () {
      var prevBed = -1.0;
      var prevThr = double.infinity;
      for (var d = 0; d <= 10; d++) {
        final bed = Squelch.bedLevelFromDetent(d);
        final thr = Squelch.gateThresholdFromDetent(d);
        expect(bed, greaterThanOrEqualTo(prevBed), reason: 'bed $d');
        expect(thr, lessThan(prevThr), reason: 'thr $d');
        prevBed = bed;
        prevThr = thr;
      }
    });

    test('rejects out-of-range detents', () {
      expect(() => Squelch.bedLevelFromDetent(-1), throwsArgumentError);
      expect(() => Squelch.bedLevelFromDetent(11), throwsArgumentError);
      expect(() => Squelch.gateThresholdFromDetent(99), throwsArgumentError);
    });
  });

  group('RxGate', () {
    test('closed gate emits silence; loud block opens it', () {
      final gate = RxGate(threshold: 0.1);
      final out = Float32List(480);
      gate.process(Float32List(480), out);
      expect(gate.isOpen, isFalse);
      expect(out.every((s) => s == 0), isTrue);

      final loud = Float32List.fromList(List.filled(480, 0.5));
      gate.process(loud, out);
      expect(gate.isOpen, isTrue);
      expect(out[0], 0.5);
    });

    test('hysteresis keeps the gate open through a modest dip', () {
      final gate = RxGate(threshold: 0.2);
      gate.process(Float32List.fromList(List.filled(200, 0.4)), Float32List(200));
      expect(gate.isOpen, isTrue);
      // 0.12 is below 0.2 but above 0.2 * 0.5 = 0.1
      gate.process(Float32List.fromList(List.filled(200, 0.12)), Float32List(200));
      expect(gate.isOpen, isTrue);
      gate.process(Float32List.fromList(List.filled(200, 0.04)), Float32List(200));
      expect(gate.isOpen, isFalse);
    });
  });

  group('VoiceRxProcessor', () {
    test('default intensity is Light and default detent is 5', () {
      final rx = VoiceRxProcessor();
      expect(rx.intensity, CharacterIntensity.light);
      expect(rx.squelchDetent, 5);
      expect(rx.restingBedLevel, Squelch.bedLevelFromDetent(5));
    });

    test('closed squelch + silence stays silent on the voice bus', () {
      final rx = VoiceRxProcessor(
        intensity: CharacterIntensity.full,
        squelchDetent: 0,
      );
      final out = rx.process(Float32List(1024));
      expect(rx.isGateOpen, isFalse);
      expect(out.every((s) => s == 0), isTrue);
    });

    test('loud in-band tone opens the gate and leaves the DSP', () {
      final rx = VoiceRxProcessor(
        intensity: CharacterIntensity.full,
        squelchDetent: 10,
      );
      final n = 4800;
      final input = Float32List(n);
      for (var i = 0; i < n; i++) {
        input[i] = 0.4 * math.sin(2 * math.pi * 1000 * i / 48000);
      }
      final out = rx.process(input);
      expect(rx.isGateOpen, isTrue);
      expect(RxGate.rmsOf(out), greaterThan(0.05));
    });

    test('Off + open gate is a bypass of the gated buffer', () {
      final rx = VoiceRxProcessor(
        intensity: CharacterIntensity.off,
        squelchDetent: 10,
      );
      final input = Float32List.fromList(List.filled(1024, 0.3));
      final out = rx.process(input);
      expect(rx.isGateOpen, isTrue);
      for (var i = 0; i < input.length; i++) {
        expect(out[i], input[i]);
      }
    });
  });

  group('SfxEngine.applySquelch', () {
    test('detent 0 silences beds; detent 10 is the faint cap', () {
      final sink = RecordingAudioSink();
      final engine = SfxEngine(sink: sink);
      engine.applySquelch(0);
      expect(engine.bedLevel, 0);
      expect(sink.loopGains[SfxId.staticBed1], 0);
      expect(sink.loopGains[SfxId.staticBed2], 0);
      expect(sink.loopGains[SfxId.staticBed3], 0);

      engine.applySquelch(10);
      expect(engine.bedLevel, Squelch.maxRestingBed);
      final expected = BedMixer.gainsFor(Squelch.maxRestingBed);
      expect(sink.loopGains[SfxId.staticBed1], closeTo(expected.bed1, 1e-12));
      expect(sink.loopGains[SfxId.staticBed2], closeTo(expected.bed2, 1e-12));
      expect(sink.loopGains[SfxId.staticBed3], closeTo(expected.bed3, 1e-12));
      engine.dispose();
    });
  });

  group('duck release scheduler', () {
    test('fires the restoring setBusGainDb without a host tick()', () {
      final sink = RecordingAudioSink();
      late void Function() pending;
      Duration? scheduled;
      final clock = _Clock();
      final engine = SfxEngine(
        sink: sink,
        now: clock.now,
        scheduleDuckRelease: (delay, onFire) {
          scheduled = delay;
          pending = onFire;
        },
      );
      engine.play(SfxId.squelchOpen); // 60 ms
      expect(engine.isVoiceDucked, isTrue);
      expect(scheduled, const Duration(milliseconds: 60));

      clock.advance(const Duration(milliseconds: 60));
      pending();
      expect(engine.isVoiceDucked, isFalse);
      expect(sink.events.whereType<SetBusGainEvent>().last.gainDb, 0);
      engine.dispose();
    });
  });
}

final class _Clock {
  DateTime _now = DateTime.utc(2026, 1, 1);
  DateTime now() => _now;
  void advance(Duration d) => _now = _now.add(d);
}
