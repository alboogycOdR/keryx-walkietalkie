import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/audio/audio.dart';

double _dbToLinear(double db) => math.pow(10.0, db / 20.0).toDouble();

void main() {
  late _FakeBackend backend;
  late DeviceAudioSink sink;

  setUp(() {
    backend = _FakeBackend();
    sink = DeviceAudioSink(backend: backend);
  });

  tearDown(() async {
    if (sink.isInitialized) {
      await sink.dispose();
    }
  });

  test('initialize loads every §7.1 WAV exactly once', () async {
    await sink.initialize();
    expect(sink.isInitialized, isTrue);
    final expected = SfxManifest.all.map((e) => e.assetPath).toSet();
    expect(backend.loaded.toSet(), expected);
    expect(backend.loaded, hasLength(SfxId.values.length));
    expect(SfxId.values, hasLength(22));
    await sink.initialize();
    expect(backend.loaded, hasLength(22), reason: 'second init is a no-op');
  });

  test('playOneShot starts a non-looping voice on the given bus', () async {
    await sink.initialize();
    sink.playOneShot(
      id: SfxId.keyClick,
      bus: AudioBus.sfx,
      assetPath: SfxManifest.lookup(SfxId.keyClick).assetPath,
      gain: 0.8,
    );
    expect(backend.voices, hasLength(1));
    final voice = backend.voices.values.single;
    expect(voice.assetPath, 'assets/sfx/v1/key_click.wav');
    expect(voice.bus, AudioBus.sfx);
    expect(voice.volume, 0.8);
    expect(voice.looping, isFalse);
  });

  test('three beds loop simultaneously with independent setLoopGain', () async {
    await sink.initialize();
    for (final id in BedGains.beds) {
      final entry = SfxManifest.lookup(id);
      sink.startLoop(
        id: id,
        bus: AudioBus.sfx,
        assetPath: entry.assetPath,
        loopStart: entry.loopStart,
        loopEnd: entry.resolvedLoopEnd,
        gain: 0,
      );
    }
    expect(backend.voices, hasLength(3));
    expect(backend.voices.values.every((v) => v.looping), isTrue);
    expect(
      backend.voices.values.map((v) => v.loopEnd).toSet(),
      {const Duration(milliseconds: 2000)},
    );

    sink.setLoopGain(SfxId.staticBed1, 0.25);
    sink.setLoopGain(SfxId.staticBed2, 0.5);
    sink.setLoopGain(SfxId.staticBed3, 1.0);

    final byPath = {
      for (final v in backend.voices.values) v.assetPath: v.volume,
    };
    expect(byPath['assets/sfx/v1/static_bed_1.wav'], 0.25);
    expect(byPath['assets/sfx/v1/static_bed_2.wav'], 0.5);
    expect(byPath['assets/sfx/v1/static_bed_3.wav'], 1.0);
  });

  test('setBusGainDb converts dB and applies only the SFX mix bus', () async {
    await sink.initialize();
    sink.setBusGainDb(AudioBus.sfx, AudioMix.sfxDuckVoiceDb);
    expect(sink.busGainDb(AudioBus.sfx), AudioMix.sfxDuckVoiceDb);
    expect(backend.busLinear[AudioBus.sfx], closeTo(_dbToLinear(-3), 1e-9));
    expect(
      backend.busLinear[AudioBus.voice],
      isNull,
      reason: 'voice bus is not a SoLoud destination',
    );
  });

  test('voice-bus gain is stored and pushed to onVoiceBusGain, not SoLoud SFX',
      () async {
    final voiceDb = <double>[];
    sink = DeviceAudioSink(
      backend: backend,
      onVoiceBusGain: voiceDb.add,
    );
    await sink.initialize();
    sink.setBusGainDb(AudioBus.voice, AudioMix.sfxDuckVoiceDb);
    expect(voiceDb, [AudioMix.sfxDuckVoiceDb]);
    expect(sink.voiceBusGainLinear, closeTo(_dbToLinear(-3), 1e-9));
    expect(backend.busLinear[AudioBus.voice], isNull);
    expect(backend.busLinear[AudioBus.sfx], 1.0);
  });

  test('stop and stopAll end the matching voices', () async {
    await sink.initialize();
    sink.playOneShot(
      id: SfxId.denyBuzz,
      bus: AudioBus.sfx,
      assetPath: SfxManifest.lookup(SfxId.denyBuzz).assetPath,
    );
    sink.startLoop(
      id: SfxId.staticBed1,
      bus: AudioBus.sfx,
      assetPath: SfxManifest.lookup(SfxId.staticBed1).assetPath,
      loopStart: Duration.zero,
      loopEnd: const Duration(milliseconds: 2000),
    );
    expect(backend.voices, hasLength(2));
    sink.stop(SfxId.denyBuzz);
    expect(backend.voices, hasLength(1));
    sink.stopAll();
    expect(backend.voices, isEmpty);
  });

  test('contract methods throw before initialize and after dispose', () async {
    expect(
      () => sink.playOneShot(
        id: SfxId.powerOn,
        bus: AudioBus.sfx,
        assetPath: SfxManifest.lookup(SfxId.powerOn).assetPath,
      ),
      throwsStateError,
    );
    await sink.initialize();
    await sink.dispose();
    expect(
      () => sink.setBusGainDb(AudioBus.sfx, 0),
      throwsStateError,
    );
  });

  test('rejects non-finite gain and non-local asset paths', () async {
    await sink.initialize();
    expect(
      () => sink.playOneShot(
        id: SfxId.keyClick,
        bus: AudioBus.sfx,
        assetPath: SfxManifest.lookup(SfxId.keyClick).assetPath,
        gain: double.nan,
      ),
      throwsArgumentError,
    );
    expect(
      () => sink.playOneShot(
        id: SfxId.keyClick,
        bus: AudioBus.sfx,
        assetPath: 'https://example/not-local.wav',
      ),
      throwsArgumentError,
    );
  });

  test('SfxEngine over DeviceAudioSink still starts three SFX-bus loops',
      () async {
    await sink.initialize();
    final engine = SfxEngine(sink: sink);
    engine.setBedLevel(0.5);
    expect(backend.voices, hasLength(3));
    expect(backend.voices.values.every((v) => v.bus == AudioBus.sfx), isTrue);
    engine.play(SfxId.knobTick);
    expect(backend.busLinear[AudioBus.sfx], 1.0);
    expect(
      backend.voices.values.where((v) => !v.looping),
      hasLength(1),
    );
    engine.dispose();
  });

  test('pubspec unfreeze adds exactly flutter_soloud and permission_handler',
      () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    final depsBlock = yaml
        .split('dev_dependencies:')
        .first
        .split('dependencies:')
        .last;
    final packages = RegExp(
      r'^  ([a-z0-9_]+):',
      multiLine: true,
    ).allMatches(depsBlock).map((m) => m.group(1)!).toSet();
    expect(
      packages,
      {
        'flutter',
        'flutter_riverpod',
        'flutter_webrtc',
        'livekit_client',
        'flutter_secure_storage',
        'shared_preferences',
        'crypto',
        'qr_flutter',
        'mobile_scanner',
        'vibration',
        'flutter_soloud',
        'permission_handler',
      },
    );
  });

  test('lib/core/audio never imports permission_handler', () {
    final dartFiles = Directory('lib/core/audio')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in dartFiles) {
      expect(
        file.readAsStringSync(),
        isNot(contains('permission_handler')),
        reason: file.path,
      );
    }
  });
}

final class _FakeBackend implements PlaybackBackend {
  final List<String> loaded = <String>[];
  final Map<int, _FakeVoice> voices = <int, _FakeVoice>{};
  final Map<AudioBus, double> busLinear = <AudioBus, double>{};
  int _next = 1;
  bool _live = false;

  @override
  Future<void> initialize({
    required int sampleRateHz,
    required int bufferSize,
  }) async {
    _live = true;
    busLinear[AudioBus.sfx] = 1.0;
  }

  @override
  Future<void> loadAsset(String assetPath) async {
    if (!_live) {
      throw StateError('backend not initialized');
    }
    if (!loaded.contains(assetPath)) {
      loaded.add(assetPath);
    }
  }

  @override
  bool isLoaded(String assetPath) => loaded.contains(assetPath);

  @override
  int startVoice({
    required String assetPath,
    required AudioBus bus,
    required double volume,
    required bool looping,
    required Duration loopStart,
    required Duration loopEnd,
  }) {
    if (!_live) {
      throw StateError('backend not initialized');
    }
    if (!loaded.contains(assetPath)) {
      throw StateError('not loaded: $assetPath');
    }
    final id = _next++;
    voices[id] = _FakeVoice(
      assetPath: assetPath,
      bus: bus,
      volume: volume,
      looping: looping,
      loopStart: loopStart,
      loopEnd: loopEnd,
    );
    return id;
  }

  @override
  void setVoiceVolume(int handle, double volume) {
    final voice = voices[handle];
    if (voice == null) {
      return;
    }
    voices[handle] = voice.copyWith(volume: volume);
  }

  @override
  void stopVoice(int handle) {
    voices.remove(handle);
  }

  @override
  void setBusGainLinear(AudioBus bus, double linear) {
    if (bus == AudioBus.voice) {
      return;
    }
    busLinear[bus] = linear;
  }

  @override
  void stopAllVoices() {
    voices.clear();
  }

  @override
  Future<void> shutdown() async {
    voices.clear();
    _live = false;
  }
}

final class _FakeVoice {
  const _FakeVoice({
    required this.assetPath,
    required this.bus,
    required this.volume,
    required this.looping,
    required this.loopStart,
    required this.loopEnd,
  });

  final String assetPath;
  final AudioBus bus;
  final double volume;
  final bool looping;
  final Duration loopStart;
  final Duration loopEnd;

  _FakeVoice copyWith({double? volume}) {
    return _FakeVoice(
      assetPath: assetPath,
      bus: bus,
      volume: volume ?? this.volume,
      looping: looping,
      loopStart: loopStart,
      loopEnd: loopEnd,
    );
  }
}
