/// KERYX's single import surface for face design tokens.
library;

import 'package:flutter/material.dart';

/// Colour, typography, geometry, material, and motion tokens for the radio.
///
/// Widgets use this class instead of embedding visual literals so the face
/// remains faithful to the ratified prototype.
abstract final class KeryxTheme {
  // Housing and glass.
  static const Color shell900 = Color(0xFF15181B);
  static const Color shell700 = Color(0xFF22262A);
  static const Color shell500 = Color(0xFF31363B);
  static const Color glass = Color(0xFF0F1512);
  static const Color lcd = Color(0xFFF2A93B);
  static const Color legend = Color(0xFFCFCBC0);
  static const double ghostSegmentOpacity = 0.07;

  // Signal state. These are never decorative colours.
  static const Color tx = Color(0xFFE23D2E);
  static const Color rx = Color(0xFF7FD1A0);
  static const Color emergency = Color(0xFFFF7A18);
  static const Color olive = Color(0xFF6B7052);

  static const double grid = 8;

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
