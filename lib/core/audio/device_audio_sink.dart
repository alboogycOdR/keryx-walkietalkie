import 'dart:developer' as developer;
import 'dart:math' as math;

import 'audio_bus.dart';
import 'audio_mix.dart';
import 'audio_sink.dart';
import 'playback_backend.dart';
import 'sfx_id.dart';
import 'sfx_manifest.dart';
import 'soloud_playback_backend.dart';

/// Production [AudioSink] over SoLoud (TASK-033).
///
/// The six contract methods stay synchronous: call [initialize] once (loads
/// every §7.1 WAV into RAM) before handing the sink to [SfxEngine].
///
/// [AudioBus.sfx] gain is applied to the SoLoud SFX mix bus.
/// [AudioBus.voice] gain cannot reach WebRTC from this class — it is stored
/// and optionally pushed through [onVoiceBusGain] so TASK-037 can duck the
/// voice path. That split is a disclosed decision, not a ducking rewrite.
final class DeviceAudioSink implements AudioSink {
  DeviceAudioSink({
    PlaybackBackend? backend,
    void Function(double gainDb)? onVoiceBusGain,
  })  : _backend = backend ?? SoloudPlaybackBackend(),
        _onVoiceBusGain = onVoiceBusGain;

  /// SoLoud output buffer. 1024 frames @ 48 kHz ≈ 21 ms, under the ≤50 ms
  /// mechanical-click budget with mix/route headroom.
  static const int bufferSize = 1024;

  final PlaybackBackend _backend;
  final void Function(double gainDb)? _onVoiceBusGain;
  final Map<SfxId, List<_ActiveVoice>> _voices = <SfxId, List<_ActiveVoice>>{};
  final Map<AudioBus, double> _busGainDb = <AudioBus, double>{
    AudioBus.voice: 0,
    AudioBus.sfx: 0,
  };
  bool _ready = false;
  bool _disposed = false;

  bool get isInitialized => _ready && !_disposed;

  /// Last [setBusGainDb] value per bus (0 = unity).
  double busGainDb(AudioBus bus) => _busGainDb[bus] ?? 0;

  /// Linear amplitude for the voice bus, for a host that ducks WebRTC.
  double get voiceBusGainLinear => _dbToLinear(busGainDb(AudioBus.voice));

  /// Init SoLoud at 48 kHz and preload every §7.1 asset. Idempotent.
  Future<void> initialize() async {
    _assertNotDisposed();
    if (_ready) {
      return;
    }
    await _backend.initialize(
      sampleRateHz: AudioMix.sampleRateHz,
      bufferSize: bufferSize,
    );
    for (final entry in SfxManifest.all) {
      await _backend.loadAsset(entry.assetPath);
    }
    _backend.setBusGainLinear(AudioBus.sfx, _dbToLinear(_busGainDb[AudioBus.sfx]!));
    _ready = true;
    developer.log(
      'DeviceAudioSink ready: ${SfxManifest.entries.length} assets, '
      '${AudioMix.sampleRateHz} Hz, buffer $bufferSize',
      name: 'keryx.audio',
    );
  }

  @override
  void playOneShot({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    double gain = 1.0,
  }) {
    _assertReady();
    _checkGain(gain);
    _checkAssetPath(assetPath);
    try {
      final handle = _backend.startVoice(
        assetPath: assetPath,
        bus: bus,
        volume: gain,
        looping: false,
        loopStart: Duration.zero,
        loopEnd: Duration.zero,
      );
      _voices.putIfAbsent(id, () => <_ActiveVoice>[]).add(
            _ActiveVoice(handle: handle, gain: gain, looping: false),
          );
    } catch (error, stack) {
      developer.log(
        'playOneShot failed for ${id.assetStem}',
        name: 'keryx.audio',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  void startLoop({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    required Duration loopStart,
    required Duration loopEnd,
    double gain = 1.0,
  }) {
    _assertReady();
    _checkGain(gain);
    _checkAssetPath(assetPath);
    if (loopEnd < loopStart) {
      throw ArgumentError.value(
        loopEnd,
        'loopEnd',
        'must be >= loopStart ($loopStart)',
      );
    }
    _stopId(id);
    try {
      final handle = _backend.startVoice(
        assetPath: assetPath,
        bus: bus,
        volume: gain,
        looping: true,
        loopStart: loopStart,
        loopEnd: loopEnd,
      );
      _voices[id] = <_ActiveVoice>[
        _ActiveVoice(handle: handle, gain: gain, looping: true),
      ];
    } catch (error, stack) {
      developer.log(
        'startLoop failed for ${id.assetStem}',
        name: 'keryx.audio',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  void setLoopGain(SfxId id, double gain) {
    _assertReady();
    _checkGain(gain);
    final voices = _voices[id];
    if (voices == null) {
      return;
    }
    for (final voice in voices) {
      if (!voice.looping) {
        continue;
      }
      voice.gain = gain;
      _backend.setVoiceVolume(voice.handle, gain);
    }
  }

  @override
  void stop(SfxId id) {
    _assertReady();
    _stopId(id);
  }

  @override
  void setBusGainDb(AudioBus bus, double gainDb) {
    _assertReady();
    if (gainDb.isNaN || gainDb.isInfinite) {
      throw ArgumentError.value(gainDb, 'gainDb', 'must be finite');
    }
    _busGainDb[bus] = gainDb;
    _backend.setBusGainLinear(bus, _dbToLinear(gainDb));
    if (bus == AudioBus.voice) {
      _onVoiceBusGain?.call(gainDb);
    }
  }

  @override
  void stopAll() {
    _assertReady();
    _backend.stopAllVoices();
    _voices.clear();
  }

  /// Unload sources and shut the backend down. Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    if (_ready) {
      _backend.stopAllVoices();
      _voices.clear();
      await _backend.shutdown();
    }
    _ready = false;
    _disposed = true;
  }

  void _stopId(SfxId id) {
    final voices = _voices.remove(id);
    if (voices == null) {
      return;
    }
    for (final voice in voices) {
      _backend.stopVoice(voice.handle);
    }
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError('DeviceAudioSink is disposed');
    }
  }

  void _assertReady() {
    _assertNotDisposed();
    if (!_ready) {
      throw StateError('DeviceAudioSink.initialize() has not completed');
    }
  }

  static void _checkGain(double gain) {
    if (gain.isNaN || gain.isInfinite || gain < 0) {
      throw ArgumentError.value(gain, 'gain', 'must be a finite >= 0');
    }
  }

  static void _checkAssetPath(String assetPath) {
    if (assetPath.isEmpty) {
      throw ArgumentError.value(assetPath, 'assetPath', 'must not be empty');
    }
    if (!assetPath.startsWith(AudioMix.assetRoot)) {
      throw ArgumentError.value(
        assetPath,
        'assetPath',
        'must be a local ${AudioMix.assetRoot} asset',
      );
    }
  }

  static double _dbToLinear(double db) {
    if (db == 0) {
      return 1.0;
    }
    return math.pow(10.0, db / 20.0).toDouble();
  }
}

final class _ActiveVoice {
  _ActiveVoice({
    required this.handle,
    required this.gain,
    required this.looping,
  });

  final int handle;
  double gain;
  final bool looping;
}
