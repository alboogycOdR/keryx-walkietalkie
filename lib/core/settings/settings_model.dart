/// The selectable amount of radio-character processing applied to receive
/// audio. Kept here because it is a persistent user preference, not DSP state.
enum CharacterDspIntensity { off, light, full }

/// The locally played end-of-transmission confirmation sound.
///
/// Left byte-identical to TASK-008 — the FR-062 vs TS §7.1 divergence with
/// `RogerVariant` is out of this task's scope.
enum RogerBeepVariant { off, classic, dualTone, customPack }

/// Night-dimming preference (DS FR-108). Display and legend luminance follow
/// this auto/manual setting.
enum DimMode { auto, manual }

/// All settings that may be written on-device during phase one.
///
/// Construction still asserts in-range values so a programmer cannot
/// *write* an illegal object in debug. The read path never relies on
/// those asserts: [KeryxSettings.fromJson] clamps or defaults per field
/// so debug and release agree on corrupt storage.
class KeryxSettings {
  static const squelchLevelMin = 0;
  static const squelchLevelMax = 10;
  static const squelchLevelDefault = 5;
  static const totSecondsMin = 30;
  static const totSecondsMax = 120;
  static const totSecondsDefault = 60;
  static const voxSensitivityMin = 0;
  static const voxSensitivityMax = 10;
  static const voxSensitivityDefault = 5;
  static const voxHangTimeMsMin = 0;
  static const voxHangTimeMsMax = 60000;
  static const voxHangTimeMsDefault = 500;

  /// v2 (Technical §7): default for [preferDirectOnWifi].
  static const preferDirectOnWifiDefault = true;

  /// v2 (Technical §7): default for [messageRetentionDays] — "7 d".
  static const messageRetentionDaysMin = 1;
  static const messageRetentionDaysMax = 365;
  static const messageRetentionDaysDefault = 7;

  /// Deployment defaults for field-test builds. A saved, non-empty value wins;
  /// a blank or invalid persisted value falls back to these definitions.
  ///
  /// Deliberately still empty by construction default — countless call
  /// sites across the app (this task's own `Owned_Paths` excluded) build a
  /// bare `const KeryxSettings()` expecting "no relay configured" (LOCAL
  /// only); baking a non-empty value in here would silently flip every one
  /// of those to attempt a LINKED session (confirmed: it broke
  /// `keryx_radio_host_test.dart` and `radio_session_host_v2_test.dart`,
  /// both outside this task's territory, the first time this was tried).
  /// [relayUrlBakedIn] carries the real TASK-104 default instead, applied
  /// only at the `SettingsRepository.load()` persistence boundary.
  static const relayUrlDefault = String.fromEnvironment('KERYX_RELAY_URL');

  /// TASK-104 (owner requirements 2026-09-13): "the server relay address
  /// baked into the settings — the user is not going to know it." Applied
  /// by `SettingsRepository.load()` — never by [KeryxSettings]'s own
  /// constructor default (see [relayUrlDefault]) — so a fresh install
  /// (and a pre-existing install with an unconfigured relay) works with
  /// zero Settings interaction, while every direct `KeryxSettings()`
  /// construction elsewhere is unaffected. `--dart-define
  /// KERYX_RELAY_URL=...` still overrides it for a self-hosted/dev build.
  /// A proper domain replaces this literal once one exists.
  static const relayUrlBakedIn = String.fromEnvironment(
    'KERYX_RELAY_URL',
    defaultValue: 'wss://204-168-249-99.sslip.io',
  );
  static const tokenServiceUrlDefault = String.fromEnvironment(
    'KERYX_TOKEN_URL',
  );

  const KeryxSettings({
    this.squelchLevel = squelchLevelDefault,
    this.rogerBeep = RogerBeepVariant.classic,
    this.totSeconds = totSecondsDefault,
    this.busyLockout = true,
    this.latchMode = false,
    this.characterDspIntensity = CharacterDspIntensity.light,
    this.forceLocalOnly = false,
    this.isPro = false,
    this.dimMode = DimMode.auto,
    this.voxSensitivity = voxSensitivityDefault,
    this.voxHangTimeMs = voxHangTimeMsDefault,
    this.relayUrl = relayUrlDefault,
    this.relayUrlUserCleared = false,
    this.tokenServiceUrl = tokenServiceUrlDefault,
    this.preferDirectOnWifi = preferDirectOnWifiDefault,
    this.messageRetentionDays = messageRetentionDaysDefault,
  }) : assert(
         messageRetentionDays >= messageRetentionDaysMin &&
             messageRetentionDays <= messageRetentionDaysMax,
       ),
       assert(
         squelchLevel >= squelchLevelMin && squelchLevel <= squelchLevelMax,
       ),
       assert(totSeconds >= totSecondsMin && totSeconds <= totSecondsMax),
       assert(
         voxSensitivity >= voxSensitivityMin &&
             voxSensitivity <= voxSensitivityMax,
       ),
       assert(
         voxHangTimeMs >= voxHangTimeMsMin && voxHangTimeMs <= voxHangTimeMsMax,
       );

  final int squelchLevel;
  final RogerBeepVariant rogerBeep;
  final int totSeconds;
  final bool busyLockout;
  final bool latchMode;
  final CharacterDspIntensity characterDspIntensity;
  final bool forceLocalOnly;
  final bool isPro;

  /// Residual shim for unowned `lib/features/settings/settings_apply.dart`,
  /// which still compares `.region`. Always `global`; not persisted.
  String get region => 'global';

  /// DS FR-108 night dimming. Default auto.
  final DimMode dimMode;

  /// FR-024 VOX sensitivity slider. Persisted now; the feature is later.
  /// Discrete 0–10, same user-facing model as squelch.
  final int voxSensitivity;

  /// FR-024 VOX hang-time in milliseconds. Persisted now; the feature is later.
  final int voxHangTimeMs;

  /// WebSocket relay endpoint. An empty value means the relay is unconfigured
  /// — unless [relayUrlUserCleared] is also true, empty here is honoured
  /// literally (see [relayUrlUserCleared]).
  final String relayUrl;

  /// TASK-104: true once the user has explicitly cleared the relay override
  /// (saved it empty) at least once. While true, [relayUrl]'s empty value is
  /// never resurrected back to [relayUrlDefault] on load — distinguishing a
  /// deliberate clear from a pre-existing/legacy blob that simply never had
  /// a relay configured, which *does* fall back to the baked-in default.
  /// Flips back to false the moment the user saves a non-empty relay again.
  final bool relayUrlUserCleared;

  /// Optional token-service endpoint. When empty, [resolvedTokenServiceUrl]
  /// derives it from [relayUrl].
  final String tokenServiceUrl;

  /// v2 (Technical §7, §6.4): prefer the LAN-direct transport over the relay
  /// when both are available for the current room. Default `true`.
  final bool preferDirectOnWifi;

  /// v2 (Technical §7): local retention window, in days, before v2 voice
  /// messages (a later wave) are purged. Default 7. Kept as a plain `int`
  /// (not `Duration`) so JSON round-trips without a custom codec.
  final int messageRetentionDays;

  /// The token route is `/token` in `relay/Caddyfile`'s `@token path /token
  /// /token/*` matcher. A default derived from a `wss://` relay therefore uses
  /// the equivalent HTTPS origin and that exact path.
  String get resolvedTokenServiceUrl {
    if (tokenServiceUrl.isNotEmpty) return tokenServiceUrl;
    final relay = Uri.tryParse(relayUrl);
    if (relay == null || relay.host.isEmpty) return '';
    return relay
        .replace(scheme: 'https', path: '/token', query: null)
        .toString();
  }

  /// Closed-unit squelch for `BedMixer.gainsFor`. Persisted unit stays
  /// the integer detent 0–10; this is `squelchLevel / 10.0` (ORCH ruling).
  double get squelchNormalized => squelchLevel / squelchLevelMax;

  KeryxSettings copyWith({
    int? squelchLevel,
    RogerBeepVariant? rogerBeep,
    int? totSeconds,
    bool? busyLockout,
    bool? latchMode,
    CharacterDspIntensity? characterDspIntensity,
    bool? forceLocalOnly,
    bool? isPro,
    DimMode? dimMode,
    int? voxSensitivity,
    int? voxHangTimeMs,
    String? relayUrl,
    bool? relayUrlUserCleared,
    String? tokenServiceUrl,
    bool? preferDirectOnWifi,
    int? messageRetentionDays,
  }) => KeryxSettings(
    squelchLevel: squelchLevel ?? this.squelchLevel,
    rogerBeep: rogerBeep ?? this.rogerBeep,
    totSeconds: totSeconds ?? this.totSeconds,
    busyLockout: busyLockout ?? this.busyLockout,
    latchMode: latchMode ?? this.latchMode,
    characterDspIntensity: characterDspIntensity ?? this.characterDspIntensity,
    forceLocalOnly: forceLocalOnly ?? this.forceLocalOnly,
    isPro: isPro ?? this.isPro,
    dimMode: dimMode ?? this.dimMode,
    voxSensitivity: voxSensitivity ?? this.voxSensitivity,
    voxHangTimeMs: voxHangTimeMs ?? this.voxHangTimeMs,
    relayUrl: relayUrl ?? this.relayUrl,
    relayUrlUserCleared: relayUrlUserCleared ?? this.relayUrlUserCleared,
    tokenServiceUrl: tokenServiceUrl ?? this.tokenServiceUrl,
    preferDirectOnWifi: preferDirectOnWifi ?? this.preferDirectOnWifi,
    messageRetentionDays: messageRetentionDays ?? this.messageRetentionDays,
  );

  Map<String, Object> toJson() => {
    'squelchLevel': squelchLevel,
    'rogerBeep': rogerBeep.name,
    'totSeconds': totSeconds,
    'busyLockout': busyLockout,
    'latchMode': latchMode,
    'characterDspIntensity': characterDspIntensity.name,
    'forceLocalOnly': forceLocalOnly,
    'isPro': isPro,
    'dimMode': dimMode.name,
    'voxSensitivity': voxSensitivity,
    'voxHangTimeMs': voxHangTimeMs,
    'relayUrl': relayUrl,
    'relayUrlUserCleared': relayUrlUserCleared,
    'tokenServiceUrl': tokenServiceUrl,
    'preferDirectOnWifi': preferDirectOnWifi,
    'messageRetentionDays': messageRetentionDays,
  };

  /// Total parser: never throws. Missing / wrong-typed / out-of-range
  /// fields are clamped or defaulted independently so one bad key cannot
  /// wipe the rest of the user's configuration. Unknown v1 keys
  /// (`mode`, `region`, `channelMemory`) are ignored.
  factory KeryxSettings.fromJson(Map<String, Object?> json) {
    final userCleared = _asBool(json['relayUrlUserCleared'], false);
    return KeryxSettings(
      squelchLevel: _clampInt(
        json['squelchLevel'],
        min: squelchLevelMin,
        max: squelchLevelMax,
        fallback: squelchLevelDefault,
      ),
      rogerBeep: _enumByName(
        json['rogerBeep'],
        RogerBeepVariant.values,
        RogerBeepVariant.classic,
      ),
      totSeconds: _clampInt(
        json['totSeconds'],
        min: totSecondsMin,
        max: totSecondsMax,
        fallback: totSecondsDefault,
      ),
      busyLockout: _asBool(json['busyLockout'], true),
      latchMode: _asBool(json['latchMode'], false),
      characterDspIntensity: _enumByName(
        json['characterDspIntensity'],
        CharacterDspIntensity.values,
        CharacterDspIntensity.light,
      ),
      forceLocalOnly: _asBool(json['forceLocalOnly'], false),
      isPro: _asBool(json['isPro'], false),
      dimMode: _enumByName(json['dimMode'], DimMode.values, DimMode.auto),
      voxSensitivity: _clampInt(
        json['voxSensitivity'],
        min: voxSensitivityMin,
        max: voxSensitivityMax,
        fallback: voxSensitivityDefault,
      ),
      voxHangTimeMs: _clampInt(
        json['voxHangTimeMs'],
        min: voxHangTimeMsMin,
        max: voxHangTimeMsMax,
        fallback: voxHangTimeMsDefault,
      ),
      relayUrl: userCleared
          ? _asClearableEndpoint(
              json['relayUrl'],
              allowedSchemes: const {'wss'},
            )
          : _asEndpoint(
              json['relayUrl'],
              fallback: relayUrlBakedIn,
              allowedSchemes: const {'wss'},
            ),
      relayUrlUserCleared: userCleared,
      tokenServiceUrl: _asEndpoint(
        json['tokenServiceUrl'],
        fallback: tokenServiceUrlDefault,
        allowedSchemes: const {'https'},
      ),
      preferDirectOnWifi: _asBool(
        json['preferDirectOnWifi'],
        preferDirectOnWifiDefault,
      ),
      messageRetentionDays: _clampInt(
        json['messageRetentionDays'],
        min: messageRetentionDaysMin,
        max: messageRetentionDaysMax,
        fallback: messageRetentionDaysDefault,
      ),
    );
  }
}

int _clampInt(
  Object? value, {
  required int min,
  required int max,
  required int fallback,
}) {
  final int raw;
  if (value is int) {
    raw = value;
  } else if (value is num && value.isFinite) {
    raw = value.round();
  } else {
    return fallback;
  }
  if (raw < min) return min;
  if (raw > max) return max;
  return raw;
}

bool _asBool(Object? value, bool fallback) => value is bool ? value : fallback;

/// Accepts only secure, host-qualified endpoints. Invalid values are clamped
/// to the supplied deployment default rather than making a settings write fail.
String _asEndpoint(
  Object? value, {
  required String fallback,
  required Set<String> allowedSchemes,
}) {
  if (value is! String || value.trim().isEmpty) return fallback;
  final candidate = value.trim();
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty || !allowedSchemes.contains(uri.scheme)) {
    return fallback;
  }
  return candidate;
}

/// TASK-104: like [_asEndpoint], but for a field the user has explicitly
/// cleared — an empty/missing value is honoured as empty (never resurrected
/// to a deployment default); only a non-empty value still gets validated,
/// falling back to empty (not the default) if it is malformed.
String _asClearableEndpoint(
  Object? value, {
  required Set<String> allowedSchemes,
}) {
  if (value is! String || value.trim().isEmpty) return '';
  final candidate = value.trim();
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty || !allowedSchemes.contains(uri.scheme)) {
    return '';
  }
  return candidate;
}

T _enumByName<T extends Enum>(Object? value, List<T> values, T fallback) {
  if (value is! String) return fallback;
  for (final item in values) {
    if (item.name == value) return item;
  }
  return fallback;
}
