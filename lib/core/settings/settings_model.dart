import 'package:keryx/core/state/radio_state.dart';

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
  static const defaultRegion = 'global';

  /// Deployment defaults for field-test builds. A saved, non-empty value wins;
  /// a blank or invalid persisted value falls back to these definitions.
  static const relayUrlDefault = String.fromEnvironment('KERYX_RELAY_URL');
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
    this.region = defaultRegion,
    this.isPro = false,
    this.channelMemory = const [],
    this.dimMode = DimMode.auto,
    this.mode = RadioMode.auto,
    this.voxSensitivity = voxSensitivityDefault,
    this.voxHangTimeMs = voxHangTimeMsDefault,
    this.relayUrl = relayUrlDefault,
    this.tokenServiceUrl = tokenServiceUrlDefault,
  }) : assert(
         squelchLevel >= squelchLevelMin && squelchLevel <= squelchLevelMax,
       ),
       assert(totSeconds >= totSecondsMin && totSeconds <= totSecondsMax),
       assert(region.length > 0),
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
  final String region;
  final bool isPro;
  final List<TunedChannel> channelMemory;

  /// DS FR-108 night dimming. Default auto.
  final DimMode dimMode;

  /// FR-040 three-position mode switch. Default AUTO so a missing key
  /// matches the product default rather than inventing LOCAL.
  final RadioMode mode;

  /// FR-024 VOX sensitivity slider. Persisted now; the feature is later.
  /// Discrete 0–10, same user-facing model as squelch.
  final int voxSensitivity;

  /// FR-024 VOX hang-time in milliseconds. Persisted now; the feature is later.
  final int voxHangTimeMs;

  /// WebSocket relay endpoint. An empty value means LINKED is unconfigured.
  final String relayUrl;

  /// Optional token-service endpoint. When empty, [resolvedTokenServiceUrl]
  /// derives it from [relayUrl].
  final String tokenServiceUrl;

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
    String? region,
    bool? isPro,
    List<TunedChannel>? channelMemory,
    DimMode? dimMode,
    RadioMode? mode,
    int? voxSensitivity,
    int? voxHangTimeMs,
    String? relayUrl,
    String? tokenServiceUrl,
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
    dimMode: dimMode ?? this.dimMode,
    mode: mode ?? this.mode,
    voxSensitivity: voxSensitivity ?? this.voxSensitivity,
    voxHangTimeMs: voxHangTimeMs ?? this.voxHangTimeMs,
    relayUrl: relayUrl ?? this.relayUrl,
    tokenServiceUrl: tokenServiceUrl ?? this.tokenServiceUrl,
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
    'dimMode': dimMode.name,
    'mode': mode.name,
    'voxSensitivity': voxSensitivity,
    'voxHangTimeMs': voxHangTimeMs,
    'relayUrl': relayUrl,
    'tokenServiceUrl': tokenServiceUrl,
  };

  /// Total parser: never throws. Missing / wrong-typed / out-of-range
  /// fields are clamped or defaulted independently so one bad key cannot
  /// wipe the rest of the user's configuration.
  factory KeryxSettings.fromJson(Map<String, Object?> json) {
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
      region: _asRegion(json['region']),
      isPro: _asBool(json['isPro'], false),
      channelMemory: _readMemory(json['channelMemory']),
      dimMode: _enumByName(json['dimMode'], DimMode.values, DimMode.auto),
      mode: _enumByName(json['mode'], RadioMode.values, RadioMode.auto),
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
      relayUrl: _asEndpoint(
        json['relayUrl'],
        fallback: relayUrlDefault,
        allowedSchemes: const {'wss'},
      ),
      tokenServiceUrl: _asEndpoint(
        json['tokenServiceUrl'],
        fallback: tokenServiceUrlDefault,
        allowedSchemes: const {'https'},
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

String _asRegion(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return KeryxSettings.defaultRegion;
}

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

T _enumByName<T extends Enum>(Object? value, List<T> values, T fallback) {
  if (value is! String) return fallback;
  for (final item in values) {
    if (item.name == value) return item;
  }
  return fallback;
}

List<TunedChannel> _readMemory(Object? value) {
  if (value is! List) return const [];
  final out = <TunedChannel>[];
  for (final entry in value) {
    if (out.length >= SettingsMemoryCap.channelMemoryCapacity) break;
    if (entry is! Map) continue;
    try {
      out.add(TunedChannel.fromJson(Map<String, Object?>.from(entry)));
    } on FormatException {
      continue;
    }
  }
  return List<TunedChannel>.unmodifiable(out);
}

/// FR-009 cap, named here so the model can apply it on the read path
/// without importing the repository.
abstract final class SettingsMemoryCap {
  static const channelMemoryCapacity = 6;
}
