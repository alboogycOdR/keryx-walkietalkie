import 'dart:convert';

import 'package:keryx/core/settings/settings_store.dart';

/// Theme preference stored **additively** under its own key.
///
/// `lib/core/settings/**` is frozen (TASK-063). Night-dimming already
/// lives on `KeryxSettings.dimMode`; light/dark/system is new and must
/// not rewrite the settings blob as a reduced object (Technical §7/§10).
enum AppearanceTheme { system, light, dark }

class AppearancePreference {
  const AppearancePreference({this.theme = AppearanceTheme.dark});

  /// Dark-first (Design §3.1) and matches `lib/app.dart`'s current
  /// `keryxUxThemeData()` default. A missing stored key uses this.
  static const AppearancePreference defaults = AppearancePreference();

  static const String storageKey = 'keryx.appearance.v1';

  final AppearanceTheme theme;

  AppearancePreference copyWith({AppearanceTheme? theme}) =>
      AppearancePreference(theme: theme ?? this.theme);

  Map<String, Object> toJson() => <String, Object>{'theme': theme.name};

  factory AppearancePreference.fromJson(Map<String, Object?> json) {
    final Object? raw = json['theme'];
    if (raw is String) {
      for (final AppearanceTheme value in AppearanceTheme.values) {
        if (value.name == raw) {
          return AppearancePreference(theme: value);
        }
      }
    }
    return AppearancePreference.defaults;
  }

  @override
  bool operator ==(Object other) =>
      other is AppearancePreference && other.theme == theme;

  @override
  int get hashCode => theme.hashCode;
}

/// Persists [AppearancePreference] on a [SettingsStore] under a key
/// disjoint from `SettingsRepository.storageKey`.
class AppearanceStore {
  AppearanceStore(this._store);

  final SettingsStore _store;

  Future<AppearancePreference> load() async {
    final String? encoded = await _store.read(AppearancePreference.storageKey);
    if (encoded == null || encoded.isEmpty) {
      return AppearancePreference.defaults;
    }
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return AppearancePreference.defaults;
      }
      return AppearancePreference.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return AppearancePreference.defaults;
    }
  }

  Future<AppearancePreference> save(AppearancePreference preference) async {
    await _store.write(
      AppearancePreference.storageKey,
      jsonEncode(preference.toJson()),
    );
    return preference;
  }
}
