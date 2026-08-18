import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The selectable amount of radio-character processing applied to receive
/// audio. Kept here because it is a persistent user preference, not DSP state.
enum CharacterDspIntensity { off, light, full }

/// The locally played end-of-transmission confirmation sound.
enum RogerBeepVariant { off, classic, dualTone, customPack }

/// A previously tuned numbered channel, retained for quick recall.
class TunedChannel {
  const TunedChannel({required this.channel, required this.privacyCode})
    : assert(channel >= 1 && channel <= 99),
      assert(privacyCode >= 0 && privacyCode <= 38);

  final int channel;
  final int privacyCode;

  Map<String, int> toJson() => {'channel': channel, 'privacyCode': privacyCode};

  factory TunedChannel.fromJson(Map<String, Object?> json) {
    final channel = json['channel'];
    final privacyCode = json['privacyCode'];
    if (channel is! int || privacyCode is! int) {
      throw const FormatException(
        'A tuned channel must contain integer values.',
      );
    }
    if (channel < 1 || channel > 99 || privacyCode < 0 || privacyCode > 38) {
      throw const FormatException(
        'A tuned channel is outside the supported range.',
      );
    }
    return TunedChannel(channel: channel, privacyCode: privacyCode);
  }

  @override
  bool operator ==(Object other) =>
      other is TunedChannel &&
      other.channel == channel &&
      other.privacyCode == privacyCode;

  @override
  int get hashCode => Object.hash(channel, privacyCode);
}

/// All settings that may be written on-device during phase one.
class KeryxSettings {
  const KeryxSettings({
    this.squelchLevel = 5,
    this.rogerBeep = RogerBeepVariant.classic,
    this.totSeconds = 60,
    this.busyLockout = true,
    this.latchMode = false,
    this.characterDspIntensity = CharacterDspIntensity.light,
    this.forceLocalOnly = false,
    this.region = 'global',
    this.isPro = false,
    this.channelMemory = const [],
  }) : assert(squelchLevel >= 0 && squelchLevel <= 10),
       assert(totSeconds >= 30 && totSeconds <= 120),
       assert(region.length > 0);

  final int squelchLevel;
  final RogerBeepVariant rogerBeep;
  final int totSeconds;
  final bool busyLockout;
  final bool latchMode;
  final CharacterDspIntensity characterDspIntensity;
  final bool forceLocalOnly;
  final String region;
  final bool isPro;
  final List<TunedChannel> channelMemory;

  KeryxSettings copyWith({
    int? squelchLevel,
    RogerBeepVariant? rogerBeep,
    int? totSeconds,
    bool? busyLockout,
    bool? latchMode,
    CharacterDspIntensity? characterDspIntensity,
    bool? forceLocalOnly,
    String? region,
    bool? isPro,
    List<TunedChannel>? channelMemory,
  }) => KeryxSettings(
    squelchLevel: squelchLevel ?? this.squelchLevel,
    rogerBeep: rogerBeep ?? this.rogerBeep,
    totSeconds: totSeconds ?? this.totSeconds,
    busyLockout: busyLockout ?? this.busyLockout,
    latchMode: latchMode ?? this.latchMode,
    characterDspIntensity: characterDspIntensity ?? this.characterDspIntensity,
    forceLocalOnly: forceLocalOnly ?? this.forceLocalOnly,
    region: region ?? this.region,
    isPro: isPro ?? this.isPro,
    channelMemory: channelMemory ?? this.channelMemory,
  );

  Map<String, Object> toJson() => {
    'squelchLevel': squelchLevel,
    'rogerBeep': rogerBeep.name,
    'totSeconds': totSeconds,
    'busyLockout': busyLockout,
    'latchMode': latchMode,
    'characterDspIntensity': characterDspIntensity.name,
    'forceLocalOnly': forceLocalOnly,
    'region': region,
    'isPro': isPro,
    'channelMemory': channelMemory.map((channel) => channel.toJson()).toList(),
  };

  factory KeryxSettings.fromJson(Map<String, Object?> json) {
    T read<T>(String key) {
      final value = json[key];
      if (value is! T) throw FormatException('Invalid $key in settings.');
      return value;
    }

    final memory = read<List<Object?>>('channelMemory')
        .map(
          (entry) =>
              TunedChannel.fromJson(Map<String, Object?>.from(entry as Map)),
        )
        .toList(growable: false);
    return KeryxSettings(
      squelchLevel: read<int>('squelchLevel'),
      rogerBeep: RogerBeepVariant.values.byName(read<String>('rogerBeep')),
      totSeconds: read<int>('totSeconds'),
      busyLockout: read<bool>('busyLockout'),
      latchMode: read<bool>('latchMode'),
      characterDspIntensity: CharacterDspIntensity.values.byName(
        read<String>('characterDspIntensity'),
      ),
      forceLocalOnly: read<bool>('forceLocalOnly'),
      region: read<String>('region'),
      isPro: read<bool>('isPro'),
      channelMemory: memory,
    );
  }
}

/// Minimal encrypted key-value boundary, so tests never need a platform plugin.
abstract interface class SettingsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureSettingsStore implements SettingsStore {
  SecureSettingsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Test-only-friendly store that keeps encrypted-store-shaped values in memory.
class InMemorySettingsStore implements SettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// Local-only persistence. This repository intentionally has no network API.
class SettingsRepository {
  SettingsRepository(this._store);

  static const _storageKey = 'keryx.settings.v1';
  static const channelMemoryCapacity = 6;

  final SettingsStore _store;

  Future<KeryxSettings> load() async {
    final encoded = await _store.read(_storageKey);
    if (encoded == null) return const KeryxSettings();
    try {
      return KeryxSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(encoded) as Map),
      );
    } on FormatException {
      return const KeryxSettings();
    } on ArgumentError {
      return const KeryxSettings();
    }
  }

  Future<KeryxSettings> save(KeryxSettings settings) async {
    _validate(settings);
    await _store.write(_storageKey, jsonEncode(settings.toJson()));
    return settings;
  }

  /// Records a tune at the head of quick recall, de-duplicating its prior slot.
  Future<KeryxSettings> rememberChannel(TunedChannel channel) async {
    final current = await load();
    final memory = [
      channel,
      ...current.channelMemory.where((entry) => entry != channel),
    ].take(channelMemoryCapacity).toList(growable: false);
    return save(current.copyWith(channelMemory: memory));
  }

  void _validate(KeryxSettings settings) {
    if (settings.squelchLevel < 0 || settings.squelchLevel > 10) {
      throw ArgumentError.value(
        settings.squelchLevel,
        'squelchLevel',
        'Must be 0–10.',
      );
    }
    if (settings.totSeconds < 30 || settings.totSeconds > 120) {
      throw ArgumentError.value(
        settings.totSeconds,
        'totSeconds',
        'Must be 30–120 seconds.',
      );
    }
    if (settings.region.trim().isEmpty) {
      throw ArgumentError.value(
        settings.region,
        'region',
        'Must not be empty.',
      );
    }
    if (settings.channelMemory.length > channelMemoryCapacity) {
      throw ArgumentError.value(
        settings.channelMemory,
        'channelMemory',
        'Maximum is six.',
      );
    }
  }
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SecureSettingsStore(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(settingsStoreProvider)),
);

final settingsProvider = FutureProvider<KeryxSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).load(),
);
