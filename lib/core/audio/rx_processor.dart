import 'dart:typed_data';

import 'character_chain.dart';
import 'squelch.dart';

/// End-to-end voice-bus RX transform: energy gate then radio character DSP.
///
/// Buffer-in / buffer-out. Independent of WebRTC / LiveKit.
final class VoiceRxProcessor {
  VoiceRxProcessor({
    CharacterIntensity intensity = CharacterIntensity.light,
    int squelchDetent = 5,
    double sampleRateHz = 48000,
    int hissSeed = 0x4B455258,
  })  : _chain = RadioCharacterChain(
          intensity: intensity,
          sampleRateHz: sampleRateHz,
          hissSeed: hissSeed,
        ),
        _gate = RxGate(threshold: Squelch.gateThresholdFromDetent(squelchDetent)),
        _squelchDetent = squelchDetent {
    Squelch.checkDetent(squelchDetent);
  }

  final RadioCharacterChain _chain;
  final RxGate _gate;
  int _squelchDetent;

  CharacterIntensity get intensity => _chain.intensity;

  set intensity(CharacterIntensity value) => _chain.intensity = value;

  int get squelchDetent => _squelchDetent;

  set squelchDetent(int value) {
    Squelch.checkDetent(value);
    _squelchDetent = value;
    _gate.threshold = Squelch.gateThresholdFromDetent(value);
  }

  bool get isGateOpen => _gate.isOpen;

  RadioCharacterChain get chain => _chain;

  /// Resting hiss bed level for [SfxEngine.setBedLevel] / [SfxEngine.applySquelch].
  double get restingBedLevel => Squelch.bedLevelFromDetent(_squelchDetent);

  Float32List process(Float32List input) {
    final gated = Float32List(input.length);
    _gate.process(input, gated);
    // Resting hiss lives on the SFX bed. Mix the DSP hiss floor only while
    // the gate is open so a closed squelch stays silent on the voice bus.
    _chain.hissLevel = _gate.isOpen ? Squelch.bedLevelFromDetent(_squelchDetent) : 0;
    return _chain.process(gated);
  }

  void reset() {
    _gate.reset();
    _chain.reset();
  }
}
