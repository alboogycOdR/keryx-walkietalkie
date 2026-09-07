/// Successor (Wave-4) design tokens — Design spec §3, additive to [KeryxTheme].
///
/// The hardware-faceplate token set in `theme.dart` stays the source of truth
/// for the legacy face until TASK-061. New screens consume [KeryxUxTokens]
/// via `Theme.of(context).extension<KeryxUxTokens>()` (or [keryxUxThemeData]).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.x contrast ratio using Flutter's own relative-luminance definition.
double keryxContrastRatio(Color a, Color b) {
  final double l1 = a.computeLuminance();
  final double l2 = b.computeLuminance();
  final double lighter = math.max(l1, l2);
  final double darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Design §3.2 token names. Eleven entries; names match the spec table
/// character-for-character (slash form), so tests can enumerate them.
enum KeryxUxColorName {
  surfaceBase('surface/base'),
  surfaceCard('surface/card'),
  surfaceRaised('surface/raised'),
  textPrimary('text/primary'),
  textSecondary('text/secondary'),
  borderDefault('border/default'),
  actionPrimary('action/primary'),
  stateTx('state/tx'),
  stateRx('state/rx'),
  stateWarning('state/warning'),
  stateEmergency('state/emergency');

  const KeryxUxColorName(this.specName);

  /// Spec table name, e.g. `surface/base`.
  final String specName;
}

/// One complete 11-token palette (dark or light). Hexes are Design §3.2
/// verbatim — contrast failures are not silently substituted here.
@immutable
class KeryxUxPalette {
  const KeryxUxPalette({
    required this.surfaceBase,
    required this.surfaceCard,
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textSecondary,
    required this.borderDefault,
    required this.actionPrimary,
    required this.stateTx,
    required this.stateRx,
    required this.stateWarning,
    required this.stateEmergency,
  });

  final Color surfaceBase;
  final Color surfaceCard;
  final Color surfaceRaised;
  final Color textPrimary;
  final Color textSecondary;
  final Color borderDefault;
  final Color actionPrimary;
  final Color stateTx;
  final Color stateRx;
  final Color stateWarning;
  final Color stateEmergency;

  /// Design §3.2 dark column, verbatim.
  static const KeryxUxPalette dark = KeryxUxPalette(
    surfaceBase: Color(0xFF101318),
    surfaceCard: Color(0xFF1B2028),
    surfaceRaised: Color(0xFF252C36),
    textPrimary: Color(0xFFF4F6F8),
    textSecondary: Color(0xFFA7B0BD),
    borderDefault: Color(0xFF343D49),
    actionPrimary: Color(0xFF4D8DFF),
    stateTx: Color(0xFFE45A52),
    stateRx: Color(0xFF55C39A),
    stateWarning: Color(0xFFF0B44C),
    stateEmergency: Color(0xFFF28C45),
  );

  /// Design §3.2 light column, verbatim.
  static const KeryxUxPalette light = KeryxUxPalette(
    surfaceBase: Color(0xFFF7F8FA),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFE9EDF3),
    textPrimary: Color(0xFF18202A),
    textSecondary: Color(0xFF566272),
    borderDefault: Color(0xFFD5DCE5),
    actionPrimary: Color(0xFF2467D9),
    stateTx: Color(0xFFB52F2B),
    stateRx: Color(0xFF167D58),
    stateWarning: Color(0xFF936000),
    stateEmergency: Color(0xFFA94A09),
  );

  Color operator [](KeryxUxColorName name) {
    switch (name) {
      case KeryxUxColorName.surfaceBase:
        return surfaceBase;
      case KeryxUxColorName.surfaceCard:
        return surfaceCard;
      case KeryxUxColorName.surfaceRaised:
        return surfaceRaised;
      case KeryxUxColorName.textPrimary:
        return textPrimary;
      case KeryxUxColorName.textSecondary:
        return textSecondary;
      case KeryxUxColorName.borderDefault:
        return borderDefault;
      case KeryxUxColorName.actionPrimary:
        return actionPrimary;
      case KeryxUxColorName.stateTx:
        return stateTx;
      case KeryxUxColorName.stateRx:
        return stateRx;
      case KeryxUxColorName.stateWarning:
        return stateWarning;
      case KeryxUxColorName.stateEmergency:
        return stateEmergency;
    }
  }

  /// Spec-name → colour, for enumeration tests.
  Map<String, Color> get bySpecName => <String, Color>{
    for (final KeryxUxColorName name in KeryxUxColorName.values)
      name.specName: this[name],
  };

  /// Text/icon colour that meets [floor] against [fill], preferring palette
  /// tokens then black/white. Never mutates [fill] — this is an on-fill
  /// helper, not a silent substitution of a failed spec hex.
  Color contrastingOn(Color fill, {double floor = 4.5}) {
    const Color white = Color(0xFFFFFFFF);
    const Color black = Color(0xFF000000);
    final List<Color> candidates = <Color>[
      textPrimary,
      textSecondary,
      surfaceBase,
      surfaceCard,
      surfaceRaised,
      white,
      black,
    ];
    Color? best;
    double bestRatio = -1;
    Color? fallback;
    double fallbackRatio = -1;
    for (final Color c in candidates) {
      if (c == fill) {
        continue;
      }
      final double r = keryxContrastRatio(c, fill);
      if (r > fallbackRatio) {
        fallback = c;
        fallbackRatio = r;
      }
      if (r >= floor && r > bestRatio) {
        best = c;
        bestRatio = r;
      }
    }
    return best ?? fallback!;
  }

  KeryxUxPalette lerp(KeryxUxPalette other, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KeryxUxPalette(
      surfaceBase: l(surfaceBase, other.surfaceBase),
      surfaceCard: l(surfaceCard, other.surfaceCard),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      borderDefault: l(borderDefault, other.borderDefault),
      actionPrimary: l(actionPrimary, other.actionPrimary),
      stateTx: l(stateTx, other.stateTx),
      stateRx: l(stateRx, other.stateRx),
      stateWarning: l(stateWarning, other.stateWarning),
      stateEmergency: l(stateEmergency, other.stateEmergency),
    );
  }
}

/// Colour as a *redundant* cue: a caller cannot take a state colour without
/// also receiving a text label and an icon (Design §3.2, UX-FR-022).
@immutable
class KeryxUxStateCue {
  const KeryxUxStateCue({
    required this.color,
    required this.label,
    required this.icon,
  });

  final Color color;
  final String label;
  final IconData icon;
}

/// Design §3.3 type scale. Inter, sentence case at the call site. Heights are
/// multipliers of [TextStyle.fontSize] so they scale with system text scale;
/// nothing here allocates a fraction of the screen.
@immutable
class KeryxUxTypography {
  const KeryxUxTypography();

  static const String fontFamily = 'Inter';

  /// 24/30 semibold.
  static const TextStyle screenTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    height: 30 / 24,
    fontWeight: FontWeight.w600,
    fontVariations: <FontVariation>[FontVariation('wght', 600)],
  );

  /// 18/24 semibold.
  static const TextStyle sectionTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
    fontVariations: <FontVariation>[FontVariation('wght', 600)],
  );

  /// 16/24.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
    fontVariations: <FontVariation>[FontVariation('wght', 400)],
  );

  /// 14/20.
  static const TextStyle secondary = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w400,
    fontVariations: <FontVariation>[FontVariation('wght', 400)],
  );

  /// 12/16 compact metadata.
  static const TextStyle compact = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    fontVariations: <FontVariation>[FontVariation('wght', 400)],
  );

  static const List<TextStyle> scale = <TextStyle>[
    screenTitle,
    sectionTitle,
    body,
    secondary,
    compact,
  ];
}

/// Design §3.3 spacing. No full-screen height allocation (that stays on
/// the legacy [KeryxTheme.faceAllocation] only).
abstract final class KeryxUxSpacing {
  static const double grid = 8;
  static const double pageMargin = 16;
  static const double cardSpacingMin = 12;
  static const double cardSpacingMax = 16;
  static const double cardSpacing = 16;
  static const double controlGapMin = 8;
  static const double controlGapMax = 12;
  static const double controlGap = 8;
  static const double minTarget = 48;
  static const Size minTargetSize = Size(minTarget, minTarget);
}

/// Design §3.4 motion. State 120–200 ms, page/sheet 200–300 ms.
abstract final class KeryxUxMotion {
  static const Duration stateMin = Duration(milliseconds: 120);
  static const Duration stateMax = Duration(milliseconds: 200);

  /// Midpoint of the state range.
  static const Duration state = Duration(milliseconds: 160);

  static const Duration pageMin = Duration(milliseconds: 200);
  static const Duration pageMax = Duration(milliseconds: 300);

  /// Midpoint of the page/sheet range.
  static const Duration page = Duration(milliseconds: 240);

  /// Critical floor/connection changes always run [state] even under
  /// reduced motion. Decorative and page/sheet motion drop to zero.
  static Duration resolve({
    required bool reducedMotion,
    required bool critical,
    bool pageTransition = false,
  }) {
    if (critical) {
      return state;
    }
    if (reducedMotion) {
      return Duration.zero;
    }
    return pageTransition ? page : state;
  }
}

/// A sanctioned foreground/background pairing and the WCAG floor it must meet.
@immutable
class KeryxUxContrastPair {
  const KeryxUxContrastPair({
    required this.foreground,
    required this.background,
    required this.floor,
    required this.role,
  });

  final KeryxUxColorName foreground;
  final KeryxUxColorName background;
  final double floor;
  final String role;
}

/// Contrast policy for the successor tokens.
///
/// Body text (4.5:1) is sanctioned only for `text/*` on `surface/*` — those
/// twelve pairings (6 × 2 themes) all pass Design §3.2 as shipped.
///
/// Action and state colours are sanctioned as **graphical objects** (3:1)
/// on every surface, matching "colour is a redundant cue" (label + icon
/// carry the meaning; the colour is the extra). Four spec hexes miss 4.5:1
/// as 16 px body text on `surface/raised` and are therefore **not**
/// sanctioned as body text — see [specBodyTextMisses]. They are not
/// rewritten in [KeryxUxPalette].
abstract final class KeryxUxContrast {
  static const double bodyTextFloor = 4.5;
  static const double graphicalFloor = 3.0;

  static const List<KeryxUxColorName> _surfaces = <KeryxUxColorName>[
    KeryxUxColorName.surfaceBase,
    KeryxUxColorName.surfaceCard,
    KeryxUxColorName.surfaceRaised,
  ];

  static const List<KeryxUxColorName> _bodyText = <KeryxUxColorName>[
    KeryxUxColorName.textPrimary,
    KeryxUxColorName.textSecondary,
  ];

  static const List<KeryxUxColorName> _graphical = <KeryxUxColorName>[
    KeryxUxColorName.actionPrimary,
    KeryxUxColorName.stateTx,
    KeryxUxColorName.stateRx,
    KeryxUxColorName.stateWarning,
    KeryxUxColorName.stateEmergency,
  ];

  static List<KeryxUxContrastPair> get sanctionedBodyText =>
      <KeryxUxContrastPair>[
        for (final KeryxUxColorName fg in _bodyText)
          for (final KeryxUxColorName bg in _surfaces)
            KeryxUxContrastPair(
              foreground: fg,
              background: bg,
              floor: bodyTextFloor,
              role: 'body text',
            ),
      ];

  static List<KeryxUxContrastPair> get sanctionedGraphical =>
      <KeryxUxContrastPair>[
        for (final KeryxUxColorName fg in _graphical)
          for (final KeryxUxColorName bg in _surfaces)
            KeryxUxContrastPair(
              foreground: fg,
              background: bg,
              floor: graphicalFloor,
              role: 'graphical object',
            ),
      ];

  static List<KeryxUxContrastPair> get sanctioned => <KeryxUxContrastPair>[
    ...sanctionedBodyText,
    ...sanctionedGraphical,
  ];

  /// Spec-table pairings that miss 4.5:1 as body text. Not sanctioned;
  /// hexes are left verbatim. Minimal corrections (not applied):
  ///
  /// * dark `action/primary` on `surface/raised` 4.40 → `#5090FF` (~4.54)
  /// * dark `state/tx` on `surface/raised` 3.94 → `#F0665E` (~4.54)
  /// * light `action/primary` on `surface/raised` 4.45 → `#2366D8` (~4.51)
  /// * light `state/rx` on `surface/raised` 4.35 → `#137A55` (~4.53)
  static List<(Brightness, KeryxUxColorName, KeryxUxColorName)>
  get specBodyTextMisses =>
      const <(Brightness, KeryxUxColorName, KeryxUxColorName)>[
        (
          Brightness.dark,
          KeryxUxColorName.actionPrimary,
          KeryxUxColorName.surfaceRaised,
        ),
        (
          Brightness.dark,
          KeryxUxColorName.stateTx,
          KeryxUxColorName.surfaceRaised,
        ),
        (
          Brightness.light,
          KeryxUxColorName.actionPrimary,
          KeryxUxColorName.surfaceRaised,
        ),
        (
          Brightness.light,
          KeryxUxColorName.stateRx,
          KeryxUxColorName.surfaceRaised,
        ),
      ];
}

/// Flutter [ThemeExtension] for the successor visual system.
@immutable
class KeryxUxTokens extends ThemeExtension<KeryxUxTokens> {
  const KeryxUxTokens({
    required this.brightness,
    required this.palette,
    this.reducedMotion = false,
  });

  final Brightness brightness;
  final KeryxUxPalette palette;
  final bool reducedMotion;

  /// Dark is the default theme (§3.1).
  static const KeryxUxTokens dark = KeryxUxTokens(
    brightness: Brightness.dark,
    palette: KeryxUxPalette.dark,
  );

  /// Complete light theme — every token defined, not a stub (§3.1).
  static const KeryxUxTokens light = KeryxUxTokens(
    brightness: Brightness.light,
    palette: KeryxUxPalette.light,
  );

  /// [dark] is the default.
  static const KeryxUxTokens defaults = dark;

  static KeryxUxTokens of(BuildContext context) {
    return Theme.of(context).extension<KeryxUxTokens>() ?? defaults;
  }

  Color get surfaceBase => palette.surfaceBase;
  Color get surfaceCard => palette.surfaceCard;
  Color get surfaceRaised => palette.surfaceRaised;
  Color get textPrimary => palette.textPrimary;
  Color get textSecondary => palette.textSecondary;
  Color get borderDefault => palette.borderDefault;
  Color get actionPrimary => palette.actionPrimary;
  Color get stateTx => palette.stateTx;
  Color get stateRx => palette.stateRx;
  Color get stateWarning => palette.stateWarning;
  Color get stateEmergency => palette.stateEmergency;

  /// Ready / interactive action — colour plus text plus icon.
  KeryxUxStateCue get actionCue => KeryxUxStateCue(
    color: actionPrimary,
    label: 'Hold to talk',
    icon: Icons.touch_app,
  );

  KeryxUxStateCue get txCue =>
      KeryxUxStateCue(color: stateTx, label: 'Transmitting', icon: Icons.mic);

  KeryxUxStateCue get rxCue => KeryxUxStateCue(
    color: stateRx,
    label: 'Receiving',
    icon: Icons.volume_up,
  );

  KeryxUxStateCue get warningCue => KeryxUxStateCue(
    color: stateWarning,
    label: 'Channel busy',
    icon: Icons.warning_amber,
  );

  KeryxUxStateCue get emergencyCue => KeryxUxStateCue(
    color: stateEmergency,
    label: 'Emergency active',
    icon: Icons.priority_high,
  );

  List<KeryxUxStateCue> get stateCues => <KeryxUxStateCue>[
    actionCue,
    txCue,
    rxCue,
    warningCue,
    emergencyCue,
  ];

  /// Resolves a motion duration, honouring both the token flag and
  /// [MediaQuery.disableAnimationsOf].
  Duration motionFor(
    BuildContext context, {
    required bool critical,
    bool pageTransition = false,
  }) {
    final bool reduced =
        reducedMotion || MediaQuery.disableAnimationsOf(context);
    return KeryxUxMotion.resolve(
      reducedMotion: reduced,
      critical: critical,
      pageTransition: pageTransition,
    );
  }

  Duration resolveMotion({
    required bool critical,
    bool pageTransition = false,
  }) {
    return KeryxUxMotion.resolve(
      reducedMotion: reducedMotion,
      critical: critical,
      pageTransition: pageTransition,
    );
  }

  @override
  KeryxUxTokens copyWith({
    Brightness? brightness,
    KeryxUxPalette? palette,
    bool? reducedMotion,
  }) {
    return KeryxUxTokens(
      brightness: brightness ?? this.brightness,
      palette: palette ?? this.palette,
      reducedMotion: reducedMotion ?? this.reducedMotion,
    );
  }

  @override
  KeryxUxTokens lerp(ThemeExtension<KeryxUxTokens>? other, double t) {
    if (other is! KeryxUxTokens) {
      return this;
    }
    return KeryxUxTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      palette: palette.lerp(other.palette, t),
      reducedMotion: t < 0.5 ? reducedMotion : other.reducedMotion,
    );
  }
}

/// Dark-default [ThemeData] carrying [KeryxUxTokens]. Does not replace the
/// legacy [KeryxApp] shell (TASK-048 owns `lib/app.dart`).
ThemeData keryxUxThemeData({
  Brightness brightness = Brightness.dark,
  bool reducedMotion = false,
}) {
  final KeryxUxTokens tokens =
      (brightness == Brightness.dark ? KeryxUxTokens.dark : KeryxUxTokens.light)
          .copyWith(reducedMotion: reducedMotion);
  final KeryxUxPalette p = tokens.palette;
  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: p.actionPrimary,
    onPrimary: p.contrastingOn(p.actionPrimary),
    secondary: p.stateRx,
    onSecondary: p.contrastingOn(p.stateRx),
    error: p.stateWarning,
    onError: p.contrastingOn(p.stateWarning),
    surface: p.surfaceBase,
    onSurface: p.textPrimary,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: KeryxUxTypography.fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.surfaceBase,
    extensions: <ThemeExtension<dynamic>>[tokens],
  );
}
