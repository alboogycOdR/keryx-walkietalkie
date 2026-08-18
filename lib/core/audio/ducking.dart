import 'audio_mix.dart';
import 'sfx_id.dart';

/// Voice-bus duck envelope: SFX pulls voice −3 dB for ≤ 150 ms (TS §7.2).
///
/// Voice never ducks the SFX bus. Cosmetic SFX do not start a duck.
final class DuckController {
  DuckController({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _duckUntil;

  bool get isDucking {
    _expireIfNeeded();
    return _duckUntil != null;
  }

  double get voiceGainDb => isDucking ? AudioMix.sfxDuckVoiceDb : 0.0;

  /// Apply a one-shot's duck window. Returns true if voice gain changed.
  bool noteSfx(SfxId id, Duration duration) {
    _expireIfNeeded();
    if (!id.ducksVoice) {
      return false;
    }
    final window = duration > AudioMix.maxDuck ? AudioMix.maxDuck : duration;
    final until = _now().add(window);
    if (_duckUntil == null || until.isAfter(_duckUntil!)) {
      final wasDucking = _duckUntil != null;
      _duckUntil = until;
      return !wasDucking;
    }
    return false;
  }

  /// Advance the envelope (call after the injected clock moves).
  bool tick() {
    final was = _duckUntil != null;
    _expireIfNeeded();
    return was && _duckUntil == null;
  }

  void reset() {
    _duckUntil = null;
  }

  void _expireIfNeeded() {
    final until = _duckUntil;
    if (until != null && !_now().isBefore(until)) {
      _duckUntil = null;
    }
  }
}
