import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_bus.dart';
import 'playback_backend.dart';

/// [PlaybackBackend] over `flutter_soloud`.
///
/// SFX voices ride a dedicated mix bus so [AudioSink.setBusGainDb] on
/// [AudioBus.sfx] is one SoLoud volume write. [AudioBus.voice] is not a
/// SoLoud destination — WebRTC owns that path — so voice-bus gain is a
/// no-op here; [DeviceAudioSink] stores it and notifies the host.
final class SoloudPlaybackBackend implements PlaybackBackend {
  SoloudPlaybackBackend({SoLoud? soloud}) : _soloud = soloud ?? SoLoud.instance;

  final SoLoud _soloud;
  final Map<String, AudioSource> _sources = <String, AudioSource>{};
  final Map<int, SoundHandle> _voices = <int, SoundHandle>{};
  Bus? _sfxBus;
  int _nextHandle = 1;
  bool _initialized = false;

  static const int _maxVoices = 32;

  @override
  Future<void> initialize({
    required int sampleRateHz,
    required int bufferSize,
  }) async {
    try {
      await _soloud.init(
        sampleRate: sampleRateHz,
        bufferSize: bufferSize,
        channels: Channels.stereo,
        lowLatency: true,
      );
      _soloud.setMaxActiveVoiceCount(_maxVoices);
      final bus = _soloud.createMixingBus(name: 'keryx.sfx');
      bus.playOnEngine(volume: 1.0);
      _sfxBus = bus;
      _initialized = true;
    } catch (error, stack) {
      developer.log(
        'SoLoud init failed',
        name: 'keryx.audio',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  Future<void> loadAsset(String assetPath) async {
    _assertLive();
    if (_sources.containsKey(assetPath)) {
      return;
    }
    try {
      final source = await _soloud.loadAsset(
        assetPath,
        mode: LoadMode.memory,
      );
      _sources[assetPath] = source;
    } catch (error, stack) {
      developer.log(
        'SoLoud loadAsset failed for $assetPath',
        name: 'keryx.audio',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  bool isLoaded(String assetPath) => _sources.containsKey(assetPath);

  @override
  int startVoice({
    required String assetPath,
    required AudioBus bus,
    required double volume,
    required bool looping,
    required Duration loopStart,
    required Duration loopEnd,
  }) {
    _assertLive();
    final source = _sources[assetPath];
    if (source == null) {
      throw StateError('SFX asset not loaded: $assetPath');
    }
    final sfxBus = _sfxBus;
    // SFX always plays on the SFX mix bus. Voice-bus plays are not a
    // device-audio path (WebRTC owns voice); they still go through SFX so
    // a mis-routed call is audible rather than silent.
    final busId = sfxBus?.busId ?? 0;
    final _ = bus;
    try {
      final handle = _soloud.play(
        source,
        busId: busId,
        volume: volume,
        looping: looping,
        loopingStartAt: loopStart,
        loopingEndAt: looping ? loopEnd : null,
      );
      final id = _nextHandle++;
      _voices[id] = handle;
      return id;
    } catch (error, stack) {
      developer.log(
        'SoLoud play failed for $assetPath',
        name: 'keryx.audio',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  @override
  void setVoiceVolume(int handle, double volume) {
    final voice = _voices[handle];
    if (voice == null) {
      return;
    }
    _soloud.setVolume(voice, volume);
  }

  @override
  void stopVoice(int handle) {
    final voice = _voices.remove(handle);
    if (voice == null) {
      return;
    }
    // AudioSink.stop is synchronous; SoLoud.stop is not.
    unawaited(_soloud.stop(voice));
  }

  @override
  void setBusGainLinear(AudioBus bus, double linear) {
    if (bus != AudioBus.sfx) {
      return;
    }
    final sfxBus = _sfxBus;
    final handle = sfxBus?.soundHandle;
    if (handle == null) {
      return;
    }
    _soloud.setVolume(handle, linear);
  }

  @override
  void stopAllVoices() {
    for (final handle in _voices.values.toList(growable: false)) {
      unawaited(_soloud.stop(handle));
    }
    _voices.clear();
  }

  @override
  Future<void> shutdown() async {
    stopAllVoices();
    for (final source in _sources.values) {
      await _soloud.disposeSource(source);
    }
    _sources.clear();
    _sfxBus?.dispose();
    _sfxBus = null;
    if (_initialized && _soloud.isInitialized) {
      _soloud.deinit();
    }
    _initialized = false;
  }

  void _assertLive() {
    if (!_initialized || !_soloud.isInitialized) {
      throw StateError('SoLoud backend is not initialized');
    }
  }
}
