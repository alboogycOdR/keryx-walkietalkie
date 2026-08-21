import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_model.dart';
import 'settings_store.dart';

export 'settings_model.dart';
export 'settings_store.dart';

/// Local-only persistence. This repository intentionally has no network API.
class SettingsRepository {
  SettingsRepository(this._store);

  static const storageKey = 'keryx.settings.v1';
  static const channelMemoryCapacity = SettingsMemoryCap.channelMemoryCapacity;

  final SettingsStore _store;
  final StreamController<KeryxSettings> _changes =
      StreamController<KeryxSettings>.broadcast();

  /// Completes in FIFO order so overlapping [save]/[rememberChannel]
  /// calls cannot lose an update (TS §6.2: 12 channel crossings/s).
  Future<void> _writeChain = Future<void>.value();

  /// Emits after every successful [save] or [rememberChannel].
  Stream<KeryxSettings> get changes => _changes.stream;

  Future<KeryxSettings> load() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null || encoded.isEmpty) return const KeryxSettings();
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const KeryxSettings();
      return KeryxSettings.fromJson(Map<String, Object?>.from(decoded));
    } on Object catch (error, stackTrace) {
      developer.log(
        'Stored settings blob was unusable; using defaults.',
        name: 'keryx.settings',
        error: error,
        stackTrace: stackTrace,
      );
      return const KeryxSettings();
    }
  }

  Future<KeryxSettings> save(KeryxSettings settings) {
    return _serialized(() => _saveUnlocked(settings));
  }

  /// Records a tune at the head of quick recall, de-duplicating its prior slot.
  Future<KeryxSettings> rememberChannel(TunedChannel channel) {
    return _serialized(() async {
      final current = await load();
      final memory = [
        channel,
        ...current.channelMemory.where((entry) => entry != channel),
      ].take(channelMemoryCapacity).toList(growable: false);
      return _saveUnlocked(current.copyWith(channelMemory: memory));
    });
  }

  void dispose() {
    _changes.close();
  }

  Future<KeryxSettings> _saveUnlocked(KeryxSettings settings) async {
    _validate(settings);
    await _store.write(storageKey, jsonEncode(settings.toJson()));
    if (!_changes.isClosed) {
      _changes.add(settings);
    }
    return settings;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeChain = _writeChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _validate(KeryxSettings settings) {
    if (settings.squelchLevel < KeryxSettings.squelchLevelMin ||
        settings.squelchLevel > KeryxSettings.squelchLevelMax) {
      throw ArgumentError.value(
        settings.squelchLevel,
        'squelchLevel',
        'Must be ${KeryxSettings.squelchLevelMin}–${KeryxSettings.squelchLevelMax}.',
      );
    }
    if (settings.totSeconds < KeryxSettings.totSecondsMin ||
        settings.totSeconds > KeryxSettings.totSecondsMax) {
      throw ArgumentError.value(
        settings.totSeconds,
        'totSeconds',
        'Must be ${KeryxSettings.totSecondsMin}–${KeryxSettings.totSecondsMax} seconds.',
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
    if (settings.voxSensitivity < KeryxSettings.voxSensitivityMin ||
        settings.voxSensitivity > KeryxSettings.voxSensitivityMax) {
      throw ArgumentError.value(
        settings.voxSensitivity,
        'voxSensitivity',
        'Must be ${KeryxSettings.voxSensitivityMin}–${KeryxSettings.voxSensitivityMax}.',
      );
    }
    if (settings.voxHangTimeMs < KeryxSettings.voxHangTimeMsMin ||
        settings.voxHangTimeMs > KeryxSettings.voxHangTimeMsMax) {
      throw ArgumentError.value(
        settings.voxHangTimeMs,
        'voxHangTimeMs',
        'Must be ${KeryxSettings.voxHangTimeMsMin}–${KeryxSettings.voxHangTimeMsMax} ms.',
      );
    }
  }
}

/// Live settings. Re-emits after [SettingsRepository.save] and
/// [SettingsRepository.rememberChannel] on the same repository instance,
/// so watchers never hold a one-shot first-load snapshot.
class SettingsController extends AsyncNotifier<KeryxSettings> {
  @override
  Future<KeryxSettings> build() {
    final repository = ref.watch(settingsRepositoryProvider);
    final subscription = repository.changes.listen((settings) {
      state = AsyncData(settings);
    });
    ref.onDispose(subscription.cancel);
    return repository.load();
  }

  Future<KeryxSettings> save(KeryxSettings settings) {
    return ref.read(settingsRepositoryProvider).save(settings);
  }

  Future<KeryxSettings> rememberChannel(TunedChannel channel) {
    return ref.read(settingsRepositoryProvider).rememberChannel(channel);
  }
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SecureSettingsStore(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final repository = SettingsRepository(ref.watch(settingsStoreProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

final settingsProvider =
    AsyncNotifierProvider<SettingsController, KeryxSettings>(
      SettingsController.new,
    );
