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

  final SettingsStore _store;
  final StreamController<KeryxSettings> _changes =
      StreamController<KeryxSettings>.broadcast();

  /// Completes in FIFO order so overlapping [save] calls cannot lose an
  /// update.
  Future<void> _writeChain = Future<void>.value();

  /// Emits after every successful [save].
  Stream<KeryxSettings> get changes => _changes.stream;

  /// No usable persisted blob at all (fresh install, corrupt/non-map JSON,
  /// or a decode exception) — every one of those cases carries the
  /// TASK-104 baked-in relay default, same as [KeryxSettings.fromJson]
  /// does for a *present-but-empty/unconfigured* `relayUrl` key. Only an
  /// explicit user clear (`relayUrlUserCleared`) is ever exempt, and that
  /// requires a stored blob to exist in the first place.
  static const _freshInstallDefaults = KeryxSettings(
    relayUrl: KeryxSettings.relayUrlBakedIn,
  );

  Future<KeryxSettings> load() async {
    final encoded = await _store.read(storageKey);
    if (encoded == null || encoded.isEmpty) return _freshInstallDefaults;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return _freshInstallDefaults;
      return KeryxSettings.fromJson(Map<String, Object?>.from(decoded));
    } on Object catch (error, stackTrace) {
      developer.log(
        'Stored settings blob was unusable; using defaults.',
        name: 'keryx.settings',
        error: error,
        stackTrace: stackTrace,
      );
      return _freshInstallDefaults;
    }
  }

  Future<KeryxSettings> save(KeryxSettings settings) {
    return _serialized(() => _saveUnlocked(settings));
  }

  void dispose() {
    _changes.close();
  }

  Future<KeryxSettings> _saveUnlocked(KeryxSettings settings) async {
    // TASK-104: a save with an empty relayUrl is, by construction, the user
    // explicitly clearing the field (nothing else in this codepath produces
    // one — the default is never empty). Mark it so `load()` never
    // resurrects that deliberate clear; a save with a non-empty relayUrl
    // clears the marker again, so a fresh override starts clean.
    final withClearMarker = settings.copyWith(
      relayUrlUserCleared: settings.relayUrl.trim().isEmpty,
    );
    final normalized = KeryxSettings.fromJson(withClearMarker.toJson());
    _validate(normalized);
    await _store.write(storageKey, jsonEncode(normalized.toJson()));
    if (!_changes.isClosed) {
      _changes.add(normalized);
    }
    return normalized;
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

/// Live settings. Re-emits after [SettingsRepository.save] on the same
/// repository instance, so watchers never hold a one-shot first-load snapshot.
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
