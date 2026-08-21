import 'dart:async';

import 'package:keryx/core/audio/audio.dart';
import 'package:keryx/core/floor/effects.dart';
import 'package:keryx/core/settings/settings_model.dart';
import 'package:keryx/core/state/radio_state.dart';

/// Host-agnostic §8.2 sound projection.
///
/// This is deliberately driven by plain broadcast streams rather than a
/// Riverpod provider: a session host can construct it beside the reducer and
/// [FloorEngine], while tests can feed it synchronously.
///
/// `GrantTone` has no §7.1 manifest entry. Until the manifest is amended, it
/// is intentionally projected as the cosmetic [SfxId.keyClick]. See the
/// decision table in this directory's README.
final class SfxProjection {
  SfxProjection({
    required SfxEngine engine,
    required Stream<RadioState> states,
    required Stream<FloorEffect> floorEffects,
    required Stream<KeryxSettings> settings,
    required KeryxSettings initialSettings,
    void Function(CharacterIntensity intensity)? applyCharacterIntensity,
  }) : _engine = engine,
       _applyCharacterIntensity = applyCharacterIntensity {
    _applySettings(initialSettings);
    _stateSubscription = states.listen(_onState);
    _effectsSubscription = floorEffects.listen(_onFloorEffect);
    _settingsSubscription = settings.listen(_applySettings);
  }

  final SfxEngine _engine;
  final void Function(CharacterIntensity intensity)? _applyCharacterIntensity;
  late final StreamSubscription<RadioState> _stateSubscription;
  late final StreamSubscription<FloorEffect> _effectsSubscription;
  late final StreamSubscription<KeryxSettings> _settingsSubscription;

  RadioState? _previousState;
  bool _disposed = false;

  /// Lets a polling host advance the engine's duck envelope.
  void tick() {
    _assertLive();
    _engine.tick();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateSubscription.cancel();
    await _effectsSubscription.cancel();
    await _settingsSubscription.cancel();
  }

  void _onState(RadioState state) {
    if (_disposed) return;
    final previous = _previousState;
    _previousState = state;
    if (previous == null) return;

    if (previous.phase == RadioPhase.off && state.phase == RadioPhase.boot) {
      _engine.play(SfxId.powerOn);
    }
    if (previous.phase != RadioPhase.off && state.phase == RadioPhase.off) {
      _engine.play(SfxId.powerOff);
    }
    if (previous.phase == RadioPhase.tuning && state.phase == RadioPhase.idle) {
      _engine.play(SfxId.tuneBurst);
    }
    if (!previous.isTransmitDenied && state.isTransmitDenied) {
      _engine.play(SfxId.denyBuzz);
    }
    if (!previous.isTotWarning && state.isTotWarning) {
      _engine.play(SfxId.totWarn);
    }
    if (!previous.isNoLink && state.isNoLink) {
      _engine.play(SfxId.linkLost);
    }
    if (previous.isNoLink && !state.isNoLink) {
      _engine.play(SfxId.linkUp);
    }
    if (!previous.isEmergency && state.isEmergency) {
      _engine.play(SfxId.emgAlert);
    }
    if (previous.phase != RadioPhase.rxActive &&
        state.phase == RadioPhase.rxActive) {
      _engine.play(SfxId.squelchOpen);
    }
    if (previous.phase == RadioPhase.rxActive &&
        state.phase != RadioPhase.rxActive) {
      _engine.play(SfxId.squelchTail);
      _engine.playRoger(_rogerVariant);
    }
  }

  RogerVariant _rogerVariant = RogerVariant.classicK;

  void _onFloorEffect(FloorEffect effect) {
    if (_disposed) return;
    switch (effect) {
      case GrantTone():
        _engine.play(SfxId.keyClick);
      case DenyBuzz():
        _engine.play(SfxId.denyBuzz);
      case TotWarn():
        _engine.play(SfxId.totWarn);
      case TotCut():
        _engine.play(SfxId.totCut);
      case EmgPinned():
        _engine.play(SfxId.emgAlert);
      case DispatchRadio() ||
          EmgCleared() ||
          ArbiterChanged() ||
          FloorIdleSettled():
        break;
    }
  }

  void _applySettings(KeryxSettings settings) {
    if (_disposed) return;
    _rogerVariant = rogerVariantFor(settings.rogerBeep);
    _engine.applySquelch(settings.squelchLevel);
    _applyCharacterIntensity?.call(
      characterIntensityFor(settings.characterDspIntensity),
    );
  }

  void _assertLive() {
    if (_disposed) throw StateError('SfxProjection is disposed');
  }
}

/// The sole mapping between persisted UI labels and the audio engine enums.
RogerVariant rogerVariantFor(RogerBeepVariant value) => switch (value) {
  RogerBeepVariant.off => RogerVariant.off,
  RogerBeepVariant.classic => RogerVariant.classicK,
  RogerBeepVariant.dualTone => RogerVariant.dualTone,
  // "Custom pack" has no separate Phase-1 asset, so it uses the existing
  // motorola-style manifest entry until a custom-pack asset contract exists.
  RogerBeepVariant.customPack => RogerVariant.moto,
};

/// The sole mapping between persisted DSP preference and the RX processor.
CharacterIntensity characterIntensityFor(CharacterDspIntensity value) =>
    switch (value) {
      CharacterDspIntensity.off => CharacterIntensity.off,
      CharacterDspIntensity.light => CharacterIntensity.light,
      CharacterDspIntensity.full => CharacterIntensity.full,
    };
