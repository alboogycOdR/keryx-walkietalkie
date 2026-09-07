import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';

void main() {
  group('Design §3.2 named tokens', () {
    test('enumerates all eleven spec names in both themes', () {
      expect(KeryxUxColorName.values, hasLength(11));
      const List<String> specNames = <String>[
        'surface/base',
        'surface/card',
        'surface/raised',
        'text/primary',
        'text/secondary',
        'border/default',
        'action/primary',
        'state/tx',
        'state/rx',
        'state/warning',
        'state/emergency',
      ];
      expect(
        KeryxUxColorName.values
            .map((KeryxUxColorName n) => n.specName)
            .toList(),
        specNames,
      );

      for (final KeryxUxTokens tokens in <KeryxUxTokens>[
        KeryxUxTokens.dark,
        KeryxUxTokens.light,
      ]) {
        expect(tokens.palette.bySpecName.keys, unorderedEquals(specNames));
        expect(tokens.palette.bySpecName, hasLength(11));
      }
    });

    test('dark column matches Design §3.2 verbatim', () {
      final KeryxUxPalette p = KeryxUxPalette.dark;
      expect(p.surfaceBase, const Color(0xFF101318));
      expect(p.surfaceCard, const Color(0xFF1B2028));
      expect(p.surfaceRaised, const Color(0xFF252C36));
      expect(p.textPrimary, const Color(0xFFF4F6F8));
      expect(p.textSecondary, const Color(0xFFA7B0BD));
      expect(p.borderDefault, const Color(0xFF343D49));
      expect(p.actionPrimary, const Color(0xFF4D8DFF));
      expect(p.stateTx, const Color(0xFFE45A52));
      expect(p.stateRx, const Color(0xFF55C39A));
      expect(p.stateWarning, const Color(0xFFF0B44C));
      expect(p.stateEmergency, const Color(0xFFF28C45));
    });

    test(
      'light column matches Design §3.2 verbatim (complete, not a stub)',
      () {
        final KeryxUxPalette p = KeryxUxPalette.light;
        expect(p.surfaceBase, const Color(0xFFF7F8FA));
        expect(p.surfaceCard, const Color(0xFFFFFFFF));
        expect(p.surfaceRaised, const Color(0xFFE9EDF3));
        expect(p.textPrimary, const Color(0xFF18202A));
        expect(p.textSecondary, const Color(0xFF566272));
        expect(p.borderDefault, const Color(0xFFD5DCE5));
        expect(p.actionPrimary, const Color(0xFF2467D9));
        expect(p.stateTx, const Color(0xFFB52F2B));
        expect(p.stateRx, const Color(0xFF167D58));
        expect(p.stateWarning, const Color(0xFF936000));
        expect(p.stateEmergency, const Color(0xFFA94A09));
      },
    );

    test('dark is the default theme', () {
      expect(KeryxUxTokens.defaults, KeryxUxTokens.dark);
      expect(KeryxUxTokens.defaults.brightness, Brightness.dark);
      expect(keryxUxThemeData().brightness, Brightness.dark);
      expect(
        keryxUxThemeData().extension<KeryxUxTokens>()!.brightness,
        Brightness.dark,
      );
    });
  });

  group('Contrast (WCAG AA)', () {
    test('every sanctioned pairing meets its floor', () {
      for (final KeryxUxTokens tokens in <KeryxUxTokens>[
        KeryxUxTokens.dark,
        KeryxUxTokens.light,
      ]) {
        for (final KeryxUxContrastPair pair in KeryxUxContrast.sanctioned) {
          final double ratio = keryxContrastRatio(
            tokens.palette[pair.foreground],
            tokens.palette[pair.background],
          );
          expect(
            ratio,
            greaterThanOrEqualTo(pair.floor),
            reason:
                '${tokens.brightness.name} ${pair.foreground.specName} on '
                '${pair.background.specName} (${pair.role}) = '
                '${ratio.toStringAsFixed(2)} < ${pair.floor}',
          );
        }
      }
    });

    test('does not silently ship the four spec body-text misses', () {
      for (final (
            Brightness brightness,
            KeryxUxColorName fg,
            KeryxUxColorName bg,
          )
          in KeryxUxContrast.specBodyTextMisses) {
        expect(
          KeryxUxContrast.sanctionedBodyText.where(
            (KeryxUxContrastPair p) => p.foreground == fg && p.background == bg,
          ),
          isEmpty,
          reason:
              '$fg on $bg must not be sanctioned as body text — it misses 4.5:1',
        );
        final KeryxUxPalette palette = brightness == Brightness.dark
            ? KeryxUxPalette.dark
            : KeryxUxPalette.light;
        final double ratio = keryxContrastRatio(palette[fg], palette[bg]);
        expect(
          ratio,
          lessThan(KeryxUxContrast.bodyTextFloor),
          reason:
              '${brightness.name} ${fg.specName} on ${bg.specName} '
              'was ${ratio.toStringAsFixed(2)}; finding is stale if this passes',
        );
        // Still a valid graphical cue (3:1).
        expect(ratio, greaterThanOrEqualTo(KeryxUxContrast.graphicalFloor));
      }
    });

    test('records measured ratios for the four body-text misses', () {
      double ratio(KeryxUxPalette p, KeryxUxColorName fg, KeryxUxColorName bg) {
        return keryxContrastRatio(p[fg], p[bg]);
      }

      expect(
        ratio(
          KeryxUxPalette.dark,
          KeryxUxColorName.actionPrimary,
          KeryxUxColorName.surfaceRaised,
        ),
        closeTo(4.40, 0.02),
      );
      expect(
        ratio(
          KeryxUxPalette.dark,
          KeryxUxColorName.stateTx,
          KeryxUxColorName.surfaceRaised,
        ),
        closeTo(3.94, 0.02),
      );
      expect(
        ratio(
          KeryxUxPalette.light,
          KeryxUxColorName.actionPrimary,
          KeryxUxColorName.surfaceRaised,
        ),
        closeTo(4.45, 0.02),
      );
      expect(
        ratio(
          KeryxUxPalette.light,
          KeryxUxColorName.stateRx,
          KeryxUxColorName.surfaceRaised,
        ),
        closeTo(4.35, 0.02),
      );
    });

    test('on-fill helper meets 4.5:1 against action and state fills', () {
      for (final KeryxUxPalette p in <KeryxUxPalette>[
        KeryxUxPalette.dark,
        KeryxUxPalette.light,
      ]) {
        for (final Color fill in <Color>[
          p.actionPrimary,
          p.stateTx,
          p.stateRx,
          p.stateWarning,
          p.stateEmergency,
        ]) {
          final Color onFill = p.contrastingOn(fill);
          expect(
            keryxContrastRatio(onFill, fill),
            greaterThanOrEqualTo(4.5),
            reason: 'contrastingOn($fill) = $onFill',
          );
        }
      }
    });
  });

  group('Type scale (Design §3.3)', () {
    test('five Inter steps with spec size/height/weight', () {
      expect(KeryxUxTypography.fontFamily, 'Inter');
      expect(KeryxUxTypography.scale, hasLength(5));

      expect(KeryxUxTypography.screenTitle.fontFamily, 'Inter');
      expect(KeryxUxTypography.screenTitle.fontSize, 24);
      expect(KeryxUxTypography.screenTitle.height, 30 / 24);
      expect(KeryxUxTypography.screenTitle.fontWeight, FontWeight.w600);
      expect(
        KeryxUxTypography.screenTitle.fontVariations,
        contains(const FontVariation('wght', 600)),
      );

      expect(KeryxUxTypography.sectionTitle.fontSize, 18);
      expect(KeryxUxTypography.sectionTitle.height, 24 / 18);
      expect(KeryxUxTypography.sectionTitle.fontWeight, FontWeight.w600);

      expect(KeryxUxTypography.body.fontSize, 16);
      expect(KeryxUxTypography.body.height, 24 / 16);
      expect(KeryxUxTypography.body.fontWeight, FontWeight.w400);

      expect(KeryxUxTypography.secondary.fontSize, 14);
      expect(KeryxUxTypography.secondary.height, 20 / 14);

      expect(KeryxUxTypography.compact.fontSize, 12);
      expect(KeryxUxTypography.compact.height, 16 / 12);
    });

    test('successor tokens have no full-screen height allocation', () {
      // FaceAllocation stays on the legacy KeryxTheme only.
      expect(KeryxTheme.faceAllocation.total, closeTo(1, 0.000001));
      expect(KeryxUxSpacing.grid, 8);
      expect(
        KeryxUxSpacing.pageMargin,
        isNot(KeryxTheme.faceAllocation.status),
      );
    });
  });

  group('Spacing (Design §3.3)', () {
    test('grid, margins, card spacing, control gaps, 48 dp target', () {
      expect(KeryxUxSpacing.grid, 8);
      expect(KeryxUxSpacing.pageMargin, 16);
      expect(KeryxUxSpacing.cardSpacing, inInclusiveRange(12, 16));
      expect(KeryxUxSpacing.cardSpacingMin, 12);
      expect(KeryxUxSpacing.cardSpacingMax, 16);
      expect(KeryxUxSpacing.controlGap, inInclusiveRange(8, 12));
      expect(KeryxUxSpacing.controlGapMin, 8);
      expect(KeryxUxSpacing.controlGapMax, 12);
      expect(KeryxUxSpacing.minTarget, 48);
      expect(KeryxUxSpacing.minTargetSize, const Size(48, 48));
    });
  });

  group('Motion (Design §3.4)', () {
    test('state and page durations sit in the spec ranges', () {
      expect(
        KeryxUxMotion.state.inMilliseconds,
        inInclusiveRange(
          KeryxUxMotion.stateMin.inMilliseconds,
          KeryxUxMotion.stateMax.inMilliseconds,
        ),
      );
      expect(
        KeryxUxMotion.page.inMilliseconds,
        inInclusiveRange(
          KeryxUxMotion.pageMin.inMilliseconds,
          KeryxUxMotion.pageMax.inMilliseconds,
        ),
      );
      expect(KeryxUxMotion.state, const Duration(milliseconds: 160));
      expect(KeryxUxMotion.page, const Duration(milliseconds: 240));
    });

    test('reduced motion drops decorative/page and keeps critical state', () {
      expect(
        KeryxUxMotion.resolve(reducedMotion: true, critical: true),
        KeryxUxMotion.state,
      );
      expect(
        KeryxUxMotion.resolve(reducedMotion: true, critical: false),
        Duration.zero,
      );
      expect(
        KeryxUxMotion.resolve(
          reducedMotion: true,
          critical: false,
          pageTransition: true,
        ),
        Duration.zero,
      );
      expect(
        KeryxUxMotion.resolve(
          reducedMotion: false,
          critical: false,
          pageTransition: true,
        ),
        KeryxUxMotion.page,
      );
      expect(
        KeryxUxTokens.dark
            .copyWith(reducedMotion: true)
            .resolveMotion(critical: true),
        KeryxUxMotion.state,
      );
      expect(
        KeryxUxTokens.dark
            .copyWith(reducedMotion: true)
            .resolveMotion(critical: false),
        Duration.zero,
      );
    });
  });

  group('State cues (colour is redundant)', () {
    test('every action/state token ships with a label and a Material icon', () {
      for (final KeryxUxTokens tokens in <KeryxUxTokens>[
        KeryxUxTokens.dark,
        KeryxUxTokens.light,
      ]) {
        expect(tokens.stateCues, hasLength(5));
        for (final KeryxUxStateCue cue in tokens.stateCues) {
          expect(cue.label, isNotEmpty);
          expect(cue.icon.fontFamily, 'MaterialIcons');
          expect(cue.color, isNot(tokens.textPrimary));
        }
        expect(tokens.txCue.label, 'Transmitting');
        expect(tokens.rxCue.label, 'Receiving');
        expect(tokens.warningCue.label, 'Channel busy');
        expect(tokens.emergencyCue.label, 'Emergency active');
        expect(tokens.actionCue.label, 'Hold to talk');
        expect(tokens.txCue.color, tokens.stateTx);
        expect(tokens.rxCue.color, tokens.stateRx);
      }
    });
  });

  group('Theme extension wiring', () {
    testWidgets('of(context) reads the extension; falls back to dark', (
      WidgetTester tester,
    ) async {
      late KeryxUxTokens fromTheme;
      await tester.pumpWidget(
        Theme(
          data: keryxUxThemeData(),
          child: Builder(
            builder: (BuildContext context) {
              fromTheme = KeryxUxTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(fromTheme.brightness, Brightness.dark);
      expect(fromTheme.surfaceBase, KeryxUxPalette.dark.surfaceBase);

      late KeryxUxTokens fromLight;
      await tester.pumpWidget(
        Theme(
          data: keryxUxThemeData(brightness: Brightness.light),
          child: Builder(
            builder: (BuildContext context) {
              fromLight = KeryxUxTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(fromLight.brightness, Brightness.light);
      expect(fromLight.surfaceBase, KeryxUxPalette.light.surfaceBase);
    });

    testWidgets('text scale 2.0 doubles screen-title layout height at 320 dp', (
      WidgetTester tester,
    ) async {
      Future<Size> pumpAt(double scale) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text('Channels', style: KeryxUxTypography.screenTitle),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Channels'), findsOneWidget);
        return tester.getSize(find.text('Channels'));
      }

      final Size at1 = await pumpAt(1.0);
      final Size at2 = await pumpAt(2.0);
      expect(at2.height, closeTo(at1.height * 2, 1.0));
      expect(at2.height, greaterThan(KeryxUxTypography.screenTitle.fontSize!));
    });

    testWidgets('MediaQuery disableAnimations drops decorative motion', (
      WidgetTester tester,
    ) async {
      late Duration decorative;
      late Duration critical;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: keryxUxThemeData(),
            home: Builder(
              builder: (BuildContext context) {
                final KeryxUxTokens tokens = KeryxUxTokens.of(context);
                decorative = tokens.motionFor(context, critical: false);
                critical = tokens.motionFor(context, critical: true);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(decorative, Duration.zero);
      expect(critical, KeryxUxMotion.state);
    });
  });
}
