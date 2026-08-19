import 'dart:developer' as developer;

import 'audio_bus.dart';
import 'audio_mix.dart';
import 'audio_sink.dart';
import 'bed_mixer.dart';
import 'ducking.dart';
import 'roger.dart';
import 'sfx_id.dart';
import 'sfx_manifest.dart';
import 'squelch.dart';

/// Dual-bus SFX engine (KRX-021 / KRX-024 playback).
///
/// Every play is a local `assets/sfx/v1/` file on [AudioBus.sfx]. There is no
/// network path. Device I/O is the injected [AudioSink]'s job.
final class SfxEngine {
  SfxEngine({
    required AudioSink sink,
    DateTime Function()? now,
    void Function(Duration delay, void Function() onFire)? scheduleDuckRelease,
  })  : _sink = sink,
        _duck = DuckController(now: now),
        _scheduleDuckRelease = scheduleDuckRelease;

  final AudioSink _sink;
  final DuckController _duck;
  final void Function(Duration delay, void Function() onFire)?
      _scheduleDuckRelease;
  int _duckGeneration = 0;

  double _bedLevel = 0;
  bool _bedsStarted = false;
  bool _disposed = false;

  AudioSink get sink => _sink;

  double get bedLevel => _bedLevel;

  double get voiceGainDb => _duck.voiceGainDb;

  bool get isVoiceDucked => _duck.isDucking;

  /// All SFX, including beds, ride the SFX bus. Voice is never a destination.
  AudioBus busFor(SfxId id) {
    final _ = id;
    return AudioBus.sfx;
  }

  /// Play a one-shot from the §7.1 manifest. Beds are controlled via [setBedLevel].
  void play(SfxId id) {
    _assertLive();
    if (id.isLoopBed) {
      throw ArgumentError.value(
        id,
        'id',
        'loop beds are driven by setBedLevel, not play()',
      );
    }
    final entry = SfxManifest.lookup(id);
    if (!entry.isLocalAsset) {
      throw StateError('SFX path is not a local asset: ${entry.assetPath}');
    }
    try {
      _sink.playOneShot(
        id: id,
        bus: AudioBus.sfx,
        assetPath: entry.assetPath,
        gain: 1.0,
      );
    } catch (error, stack) {
      developer.log(
        'SFX play failed for ${id.assetStem}',
        name: 'keryx.audio',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
    _applyDuck(id, entry.duration);
  }

  /// FR-062: off plays nothing; other variants map to roger_k / roger_dual / roger_moto.
  void playRoger(RogerVariant variant) {
    _assertLive();
    final id = variant.sfxId;
    if (id == null) {
      return;
    }
    play(id);
  }

  /// Map a TASK-008 squelch detent (0–10) onto the resting hiss bed (FR-061).
  void applySquelch(int detent) {
    setBedLevel(Squelch.bedLevelFromDetent(detent));
  }

  /// Squelch knob 0..1 crossfades the three loopable static beds.
  void setBedLevel(double level) {
    _assertLive();
    final gains = BedMixer.gainsFor(level);
    _bedLevel = level;
    if (!_bedsStarted) {
      for (final id in BedGains.beds) {
        final entry = SfxManifest.lookup(id);
        _sink.startLoop(
          id: id,
          bus: AudioBus.sfx,
          assetPath: entry.assetPath,
          loopStart: entry.loopStart,
          loopEnd: entry.resolvedLoopEnd,
          gain: gains[id],
        );
      }
      _bedsStarted = true;
    } else {
      for (final id in BedGains.beds) {
        _sink.setLoopGain(id, gains[id]);
      }
    }
  }

  /// Re-evaluate the duck envelope after the injected clock advances.
  void tick() {
    _assertLive();
    if (_duck.tick()) {
      _sink.setBusGainDb(AudioBus.voice, 0);
    }
  }

  void stopBeds() {
    _assertLive();
    if (!_bedsStarted) {
      return;
    }
    for (final id in BedGains.beds) {
      _sink.stop(id);
    }
    _bedsStarted = false;
    _bedLevel = 0;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _duckGeneration++;
    _sink.stopAll();
    _duck.reset();
    _sink.setBusGainDb(AudioBus.voice, 0);
    _bedsStarted = false;
    _bedLevel = 0;
    _disposed = true;
  }

  void _applyDuck(SfxId id, Duration duration) {
    if (!id.ducksVoice) {
      return;
    }
    final started = _duck.noteSfx(id, duration);
    if (started) {
      _sink.setBusGainDb(AudioBus.voice, AudioMix.sfxDuckVoiceDb);
    }
    _armDuckRelease();
  }

  void _armDuckRelease() {
    final schedule = _scheduleDuckRelease;
    if (schedule == null) {
      return;
    }
    _duckGeneration++;
    final gen = _duckGeneration;
    final delay = _duck.remaining;
    schedule(delay, () {
      if (_disposed || gen != _duckGeneration) {
        return;
      }
      tick();
    });
  }

  void _assertLive() {
    if (_disposed) {
      throw StateError('SfxEngine is disposed');
    }
  }
}
