import 'audio_bus.dart';

/// Device-side mixer used by [DeviceAudioSink].
///
/// Production code uses [SoloudPlaybackBackend]. Tests inject a fake so the
/// six [AudioSink] methods can be asserted without a native audio device.
abstract class PlaybackBackend {
  Future<void> initialize({
    required int sampleRateHz,
    required int bufferSize,
  });

  /// Decode [assetPath] into RAM. Idempotent per path.
  Future<void> loadAsset(String assetPath);

  bool isLoaded(String assetPath);

  /// Start a voice. Returns a backend-local handle id.
  int startVoice({
    required String assetPath,
    required AudioBus bus,
    required double volume,
    required bool looping,
    required Duration loopStart,
    required Duration loopEnd,
  });

  void setVoiceVolume(int handle, double volume);

  void stopVoice(int handle);

  /// Linear amplitude (1.0 = 0 dB) for an entire mix bus.
  void setBusGainLinear(AudioBus bus, double linear);

  void stopAllVoices();

  Future<void> shutdown();
}
