import 'audio_bus.dart';
import 'sfx_id.dart';

/// Playback backend. The engine never talks to a device or the network.
///
/// Production host injects [DeviceAudioSink] (SoLoud, TASK-033). Tests use
/// [RecordingAudioSink].
abstract class AudioSink {
  void playOneShot({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    double gain = 1.0,
  });

  void startLoop({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    required Duration loopStart,
    required Duration loopEnd,
    double gain = 1.0,
  });

  void setLoopGain(SfxId id, double gain);

  void stop(SfxId id);

  /// Linear gain in decibels applied to an entire bus.
  void setBusGainDb(AudioBus bus, double gainDb);

  void stopAll();
}

/// In-memory sink that records every call for unit tests.
final class RecordingAudioSink implements AudioSink {
  final List<SinkEvent> events = <SinkEvent>[];
  final Map<SfxId, double> loopGains = <SfxId, double>{};
  final Map<AudioBus, double> busGainsDb = <AudioBus, double>{
    AudioBus.voice: 0,
    AudioBus.sfx: 0,
  };
  final Set<SfxId> playing = <SfxId>{};

  @override
  void playOneShot({
    required SfxId id,
    required AudioBus bus,
    required String assetPath,
    double gain = 1.0,
  }) {
    events.add(
      PlayOneShotEvent(id: id, bus: bus, assetPath: assetPath, gain: gain),
    );
    playing.add(id);
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
    events.add(
      StartLoopEvent(
        id: id,
        bus: bus,
        assetPath: assetPath,
        loopStart: loopStart,
        loopEnd: loopEnd,
        gain: gain,
      ),
    );
    loopGains[id] = gain;
    playing.add(id);
  }

  @override
  void setLoopGain(SfxId id, double gain) {
    events.add(SetLoopGainEvent(id: id, gain: gain));
    loopGains[id] = gain;
  }

  @override
  void stop(SfxId id) {
    events.add(StopEvent(id: id));
    playing.remove(id);
    loopGains.remove(id);
  }

  @override
  void setBusGainDb(AudioBus bus, double gainDb) {
    events.add(SetBusGainEvent(bus: bus, gainDb: gainDb));
    busGainsDb[bus] = gainDb;
  }

  @override
  void stopAll() {
    events.add(const StopAllEvent());
    playing.clear();
    loopGains.clear();
  }

  Iterable<PlayOneShotEvent> get oneShots => events.whereType<PlayOneShotEvent>();

  Iterable<StartLoopEvent> get loops => events.whereType<StartLoopEvent>();
}

sealed class SinkEvent {
  const SinkEvent();
}

final class PlayOneShotEvent extends SinkEvent {
  const PlayOneShotEvent({
    required this.id,
    required this.bus,
    required this.assetPath,
    required this.gain,
  });

  final SfxId id;
  final AudioBus bus;
  final String assetPath;
  final double gain;
}

final class StartLoopEvent extends SinkEvent {
  const StartLoopEvent({
    required this.id,
    required this.bus,
    required this.assetPath,
    required this.loopStart,
    required this.loopEnd,
    required this.gain,
  });

  final SfxId id;
  final AudioBus bus;
  final String assetPath;
  final Duration loopStart;
  final Duration loopEnd;
  final double gain;
}

final class SetLoopGainEvent extends SinkEvent {
  const SetLoopGainEvent({required this.id, required this.gain});

  final SfxId id;
  final double gain;
}

final class StopEvent extends SinkEvent {
  const StopEvent({required this.id});

  final SfxId id;
}

final class SetBusGainEvent extends SinkEvent {
  const SetBusGainEvent({required this.bus, required this.gainDb});

  final AudioBus bus;
  final double gainDb;
}

final class StopAllEvent extends SinkEvent {
  const StopAllEvent();
}
