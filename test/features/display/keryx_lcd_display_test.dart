import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/theme.dart';
import 'package:keryx/features/display/keryx_lcd_display.dart';

void main() {
  Future<void> pumpDisplay(WidgetTester tester, KeryxDisplayModel model) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: KeryxLcdDisplay(model: model)),
          ),
        ),
      );

  testWidgets('renders numbered channel and privacy code in segment style', (
    tester,
  ) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel.numbered(channel: 7, code: 21),
    );

    final text = tester.widget<Text>(
      find.byKey(const Key('keryx-lcd-primary')),
    );
    expect(text.data, 'CH 07 · 21');
    expect(text.style!.fontFamily, 'DSEG7 Classic');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('keryx-lcd-ghost-segments')))
          .style!
          .color,
      KeryxTheme.lcd.withValues(alpha: KeryxTheme.ghostSegmentOpacity),
    );
  });

  testWidgets('renders keyed channels as PRV plus their user label', (
    tester,
  ) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel.private(label: 'BUSH NET'),
    );

    expect(find.byKey(const Key('keryx-lcd-primary')), findsOneWidget);
    expect(find.text('BUSH NET'), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const Key('keryx-lcd-telltale-prv')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      1,
    );
  });

  testWidgets('shows the BOOT all-segments flash', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel.numbered(channel: 1, code: 0, isBooting: true),
    );

    expect(
      tester.widget<Text>(find.byKey(const Key('keryx-lcd-primary'))).data,
      '88 · 88',
    );
  });

  testWidgets('lights each specified telltale and keeps the rest unlit', (
    tester,
  ) async {
    const active = <KeryxTelltale>{
      KeryxTelltale.tx,
      KeryxTelltale.mon,
      KeryxTelltale.prv,
      KeryxTelltale.vox,
      KeryxTelltale.emg,
      KeryxTelltale.noLink,
    };
    await pumpDisplay(
      tester,
      const KeryxDisplayModel.numbered(channel: 1, code: 0, telltales: active),
    );

    for (final indicator in active) {
      expect(_opacityFor(tester, indicator), 1);
    }
    expect(_opacityFor(tester, KeryxTelltale.replay), 0.09);
  });

  testWidgets('follows the supplied night-dimming level', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel.numbered(channel: 1, code: 0, dimLevel: 0.55),
    );

    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const Key('keryx-lcd-glass')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      0.55,
    );
  });
}

double _opacityFor(WidgetTester tester, KeryxTelltale telltale) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(Key('keryx-lcd-telltale-${telltale.name}')),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;
