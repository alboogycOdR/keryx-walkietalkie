import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/services/sound/sfx_projection.dart';

void main() {
  group('SfxProjection', () {
    test('projects state transitions with the engine duck sequence', () async {
      final h = _Harness();
      h.sink.events.clear(); // Initial squelch starts the three resting beds.

      h.states.add(const RadioState.off());
      h.states.add(const RadioState(phase: RadioPhase.boot));
      h.states.add(const RadioState(phase: RadioPhase.idle));
      h.states.add(const RadioState(phase: RadioPhase.tuning));
      h.states.add(const RadioState(phase: RadioPhase.idle));
      h.states.add(
        const RadioState(phase: RadioPhase.idle, isTransmitDenied: true),
      );
      h.states.add(const RadioState(phase: RadioPhase.idle, isNoLink: true));
      h.states.add(const RadioState(phase: RadioPhase.idle));
      h.states.add(const RadioState(phase: RadioPhase.rxActive));
      h.states.add(const RadioState(phase: RadioPhase.idle));
      h.states.add(const RadioState.off());

      expect(h.sink.events.map((event) => event.runtimeType).toList(), [
        PlayOneShotEvent,
        SetBusGainEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
        PlayOneShotEvent,
      ]);
      expect(h.sink.oneShots.map((event) => event.id), [
        SfxId.powerOn,
        SfxId.tuneBurst,
        SfxId.denyBuzz,
        SfxId.linkLost,
        SfxId.linkUp,
        SfxId.squelchOpen,
        SfxId.squelchTail,
        SfxId.rogerK,
        SfxId.powerOff,
      ]);
      expect(
        h.sink.events.whereType<SetBusGainEvent>().single.gainDb,
        AudioMix.sfxDuckVoiceDb,
      );
      await h.dispose();
    });

    test(
      'projects every audible floor effect and keeps GrantTone cosmetic',
      () async {
        final h = _Harness();
        h.sink.events.clear();

        h.effects
          ..add(const GrantTone())
          ..add(const DenyBuzz(null))
          ..add(const TotWarn())
          ..add(const TotCut())
          ..add(const EmgPinned('peer-a'));

        expect(h.sink.oneShots.map((event) => event.id), [
          SfxId.keyClick,
          SfxId.denyBuzz,
          SfxId.totWarn,
          SfxId.totCut,
          SfxId.emgAlert,
        ]);
        // keyClick does not duck. The first programme SFX does exactly once.
        expect(h.sink.events.whereType<SetBusGainEvent>(), hasLength(1));
        await h.dispose();
      },
    );

    test(
      'live settings update the next roger, squelch, and DSP mapping',
      () async {
        final mapped = <CharacterIntensity>[];
        final h = _Harness(applyCharacterIntensity: mapped.add);
        h.sink.events.clear();

        h.settings.add(
          const KeryxSettings(
            squelchLevel: 9,
            rogerBeep: RogerBeepVariant.dualTone,
            characterDspIntensity: CharacterDspIntensity.full,
          ),
        );
        h.states.add(const RadioState(phase: RadioPhase.rxActive));
        h.states.add(const RadioState(phase: RadioPhase.idle));

        expect(h.engine.bedLevel, Squelch.bedLevelFromDetent(9));
        expect(mapped, [CharacterIntensity.light, CharacterIntensity.full]);
        expect(h.sink.oneShots.map((event) => event.id), [
          SfxId.squelchTail,
          SfxId.rogerDual,
        ]);
        await h.dispose();
      },
    );

    test('enum mappings are exhaustive and stable', () {
      expect(rogerVariantFor(RogerBeepVariant.off), RogerVariant.off);
      expect(rogerVariantFor(RogerBeepVariant.classic), RogerVariant.classicK);
      expect(rogerVariantFor(RogerBeepVariant.dualTone), RogerVariant.dualTone);
      expect(rogerVariantFor(RogerBeepVariant.customPack), RogerVariant.moto);
      expect(
        CharacterDspIntensity.values.map(characterIntensityFor),
        CharacterIntensity.values,
      );
    });
  });
}

final class _Harness {
  _Harness({void Function(CharacterIntensity)? applyCharacterIntensity}) {
    projection = SfxProjection(
      engine: engine,
      states: states.stream,
      floorEffects: effects.stream,
      settings: settings.stream,
      initialSettings: const KeryxSettings(),
      applyCharacterIntensity: applyCharacterIntensity,
    );
  }

  final states = StreamController<RadioState>.broadcast(sync: true);
  final effects = StreamController<FloorEffect>.broadcast(sync: true);
  final settings = StreamController<KeryxSettings>.broadcast(sync: true);
  final sink = RecordingAudioSink();
  late final engine = SfxEngine(sink: sink);
  late final SfxProjection projection;

  Future<void> dispose() async {
    await projection.dispose();
    await states.close();
    await effects.close();
    await settings.close();
  }
}
