/// KERYX's single import surface for face design tokens.
library;

import 'package:flutter/material.dart';

/// A faceplate: KERYX's runtime-swappable set of colour/material tokens.
///
/// Faceplates change hue and material only — never layout, contrast ratios,
/// or control positions (DS §8 / FR-101). [fieldBlack] is the free default
/// and reproduces every colour TASK-005 shipped, byte-for-byte, plus the
/// glass-recess chrome TASK-012 had to hardcode because the frozen TASK-005
/// theme exposed no token for it.
@immutable
class KeryxFacePlate {
  const KeryxFacePlate({
    required this.name,
    required this.shell900,
    required this.shell700,
    required this.shell500,
    required this.glass,
    required this.lcd,
    required this.legend,
    required this.tx,
    required this.rx,
    required this.emergency,
    required this.olive,
    required this.glassBorder,
    required this.glassInnerShadowColor,
    required this.glassHighlightColor,
  });

  /// Display name for the faceplate picker (settings UI, Phase 2 packs).
  final String name;

  // Housing.
  final Color shell900;
  final Color shell700;
  final Color shell500;

  // Glass.
  final Color glass;
  final Color lcd;
  final Color legend;

  // Signal state. Faceplates may retint these, but they must never stop
  // meaning what they mean (DS §2) — that guarantee is enforced by the
  // KRX-096 per-faceplate contrast validation, not by this class.
  final Color tx;
  final Color rx;
  final Color emergency;

  /// Faceplate accent — hardware trim, knob indicator line (DS §3 `--olive`:
  /// "Faceplate accent (Field Black default: hardware trim, knob indicator
  /// line)").
  final Color olive;

  // Glass-recess chrome (PT `.glass` L51-58 inline values; TASK-012
  // hardcoded these because the frozen TASK-005 theme had no token).
  final Color glassBorder;
  final Color glassInnerShadowColor;
  final Color glassHighlightColor;

  /// The default, free faceplate (FR-101). Every value below is the exact
  /// literal TASK-005 shipped or TASK-012 hardcoded — preserved
  /// byte-for-byte and pinned by `test/core/theme/theme_test.dart`.
  static const KeryxFacePlate fieldBlack = KeryxFacePlate(
    name: 'Field Black',
    shell900: Color(0xFF15181B),
    shell700: Color(0xFF22262A),
    shell500: Color(0xFF31363B),
    glass: Color(0xFF0F1512),
    lcd: Color(0xFFF2A93B),
    legend: Color(0xFFCFCBC0),
    tx: Color(0xFFE23D2E),
    rx: Color(0xFF7FD1A0),
    emergency: Color(0xFFFF7A18),
    olive: Color(0xFF6B7052),
    glassBorder: Color(0xFF0A0F0C),
    glassInnerShadowColor: Color.fromRGBO(0, 0, 0, 0.85),
    glassHighlightColor: Color.fromRGBO(255, 255, 255, 0.05),
  );
}

/// Colour, typography, geometry, material, and motion tokens for the radio.
///
/// Widgets use this class instead of embedding visual literals so the face
/// remains faithful to the ratified prototype. Colour/material tokens below
/// are projections of the active [facePlate] (DS §8 faceplate seam, added by
/// TASK-028); layout, motion, and typography tokens are fixed across every
/// faceplate and stay plain constants.
abstract final class KeryxTheme {
  /// The faceplate currently in effect. Swap at runtime with
  /// `KeryxTheme.facePlate.value = someOtherPlate` — every colour/chrome
  /// getter below re-reads from it, so a `ValueListenableBuilder` (or an
  /// `AnimatedBuilder` listening to it) is all a widget needs to react live.
  /// Defaults to the free "Field Black" plate.
  static final ValueNotifier<KeryxFacePlate> facePlate =
      ValueNotifier<KeryxFacePlate>(KeryxFacePlate.fieldBlack);

  // Housing and glass — projections of the active facePlate.
  static Color get shell900 => facePlate.value.shell900;
  static Color get shell700 => facePlate.value.shell700;
  static Color get shell500 => facePlate.value.shell500;
  static Color get glass => facePlate.value.glass;
  static Color get lcd => facePlate.value.lcd;
  static Color get legend => facePlate.value.legend;
  static const double ghostSegmentOpacity = 0.07;

  // Signal state. These are never decorative colours.
  static Color get tx => facePlate.value.tx;
  static Color get rx => facePlate.value.rx;
  static Color get emergency => facePlate.value.emergency;
  static Color get olive => facePlate.value.olive;

  // Glass-recess chrome (PT `.glass` L51-58). Added by TASK-028 so the
  // display glass's recessed-material look has a real token to consume;
  // `lib/features/display/**` is frozen, so wiring `KeryxLcdDisplay` onto
  // these is a separate follow-on task, not done here.
  static Color get glassBorder => facePlate.value.glassBorder;
  static BoxShadow get glassInnerShadow => BoxShadow(
    color: facePlate.value.glassInnerShadowColor,
    offset: const Offset(0, 3),
    blurRadius: 10,
    blurStyle: BlurStyle.inner,
  );
  static BoxShadow get glassHighlight =>
      BoxShadow(color: facePlate.value.glassHighlightColor);

  /// The backlight-bloom gradient's outer stop (PT `.glass::after`'s
  /// `radial-gradient(..., rgba(242,169,59,.06), transparent 70%)`). Always
  /// transparent regardless of faceplate — named so call sites read as
  /// "the bloom fades to nothing", not a bare `Colors.transparent`.
  static const Color glassBloomStop = Colors.transparent;

  static const double grid = 8;

  /// Pressed keys move this far down and gain an inner shadow, per DS §4
  /// ("Pressed keys move 1 dp down, lose their top highlight, and gain an
  /// inner shadow — the same three changes on every control") / TS §6.4.
  /// Structural, not a faceplate token: every faceplate presses the same.
  static const double keyTravel = 1;

  /// Monochrome noise-overlay opacity for the moulded housing texture, per
  /// DS §4 ("Housing = `--shell-700` with a 2–3% monochrome noise overlay
  /// (moulded texture)"). Pinned to the range's upper bound: PT's own
  /// `.radio::after` noise rect uses `opacity='.035'` (3.5%), slightly hotter
  /// than DS's stated 2–3% ceiling. Flagged for ORCH rather than silently
  /// resolved — same class of PT/DS numeric drift as the settle-curve
  /// discrepancy DS §10 closed for TASK-016.
  static const double housingNoiseOverlayOpacity = 0.03;

  /// No gradient may exceed this fraction of an element's height, per DS §4
  /// ("No gradients longer than 20% of an element's height").
  static const double maxGradientHeightFraction = 0.20;

  /// Vertical face allocation, expressed as fractions of usable height.
  static const FaceAllocation faceAllocation = FaceAllocation(
    status: 0.06,
    glass: 0.18,
    grille: 0.26,
    controls: 0.22,
    ptt: 0.22,
    safeArea: 0.06,
  );

  static const Duration snapDuration = Duration(milliseconds: 140);
  static const Duration settleDuration = Duration(milliseconds: 320);
  static const Curve snapCurve = Cubic(0.2, 0.9, 0.3, 1);

  /// Prototype's ratified fast ease-out curve for elements with mass.
  static const Curve settleCurve = Cubic(0.16, 1, 0.3, 1);

  static const BoxShadow topInnerEdge = BoxShadow(
    color: Color.fromRGBO(255, 255, 255, 0.06),
    offset: Offset(0, 1),
    blurRadius: 0,
    spreadRadius: 0,
    blurStyle: BlurStyle.inner,
  );
  static const BoxShadow bottomInnerEdge = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.5),
    offset: Offset(0, -1),
    blurRadius: 0,
    spreadRadius: 0,
    blurStyle: BlurStyle.inner,
  );
  static const List<BoxShadow> raisedMaterialEdges = <BoxShadow>[
    topInnerEdge,
    bottomInnerEdge,
  ];

  static const TextStyle channelNumerals = TextStyle(
    fontFamily: 'DSEG7 Classic',
    fontSize: 56,
    height: 1,
  );
  static const TextStyle glassSecondary = TextStyle(
    fontFamily: 'Share Tech Mono',
    fontSize: 15,
    height: 1.2,
  );
  static const TextStyle telltale = TextStyle(
    fontFamily: 'Barlow Condensed',
    fontSize: 11,
    height: 1,
  );
  static const TextStyle legendLabel = TextStyle(
    fontFamily: 'Barlow Condensed',
    fontSize: 11,
    height: 1,
    fontWeight: FontWeight.w600,
    letterSpacing: 11 * 0.14,
  );
  static const TextStyle panelBody = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    height: 1.5,
  );

  /// Inter's real 600 axis (DS §3 "Interface (panels) `Inter`, 400/600"),
  /// interpolated from the single variable `Inter-Variable.ttf` asset via
  /// `FontVariation` rather than synthesised bold (TASK-001 follow-up 4 /
  /// TASK-005 follow-up 5) — no pubspec change needed, the variable font
  /// already carries the `wght` axis TASK-001 bundled.
  static const TextStyle panelBodyStrong = TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w600,
    fontVariations: <FontVariation>[FontVariation('wght', 600)],
  );
}

/// Fixed vertical allocation for the radio face.
class FaceAllocation {
  const FaceAllocation({
    required this.status,
    required this.glass,
    required this.grille,
    required this.controls,
    required this.ptt,
    required this.safeArea,
  });

  final double status;
  final double glass;
  final double grille;
  final double controls;
  final double ptt;
  final double safeArea;

  double get total => status + glass + grille + controls + ptt + safeArea;
}
