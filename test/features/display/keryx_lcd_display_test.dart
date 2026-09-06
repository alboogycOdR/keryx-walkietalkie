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

  testWidgets(
    'constructs from plain values only — no FaceScreen/session/controller types',
    (tester) async {
      // The model below is built with int/String/enum/double only. If this
      // test compiles, the constructor takes no FaceScreen, session, or
      // controller types.
      const model = KeryxDisplayModel(
        channel: 7,
        mode: 'LOCAL',
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.local},
        statusLine: 'CHANNEL CLEAR',
        signalQuality: 3,
        dimLevel: 1,
      );
      await pumpDisplay(tester, model);
      expect(find.byType(KeryxLcdDisplay), findsOneWidget);
      expect(find.byKey(const Key('keryx-lcd-glass')), findsOneWidget);
    },
  );

  testWidgets('channel readout uses DSEG7 Classic with 88 ghost segments', (
    tester,
  ) async {
    await pumpDisplay(tester, const KeryxDisplayModel(channel: 7));

    final live = tester.widget<Text>(
      find.byKey(const Key('keryx-lcd-primary')),
    );
    expect(live.data, '07');
    expect(live.style!.fontFamily, 'DSEG7 Classic');
    expect(live.style!.color, KeryxTheme.lcd);

    final ghost = tester.widget<Text>(
      find.byKey(const Key('keryx-lcd-ghost-segments')),
    );
    expect(ghost.data, '88');
    expect(ghost.style!.fontFamily, 'DSEG7 Classic');
    expect(
      ghost.style!.color,
      KeryxTheme.lcd.withValues(alpha: KeryxTheme.ghostSegmentOpacity),
    );
    expect(find.byKey(const Key('keryx-lcd-channel-prefix')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('keryx-lcd-channel-prefix')))
          .data,
      'CH',
    );
  });

  testWidgets('LOCAL lit, others ghost', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(
        channel: 1,
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.local},
      ),
    );
    expect(_opacityFor(tester, KeryxStripTelltale.local), 1);
    expect(
      _opacityFor(tester, KeryxStripTelltale.linked),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.tx),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.rx),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(_telltaleColor(tester, KeryxStripTelltale.local), KeryxTheme.lcd);
  });

  testWidgets('LINKED lit, others ghost', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(
        channel: 1,
        mode: 'LINKED',
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.linked},
      ),
    );
    expect(_opacityFor(tester, KeryxStripTelltale.linked), 1);
    expect(
      _opacityFor(tester, KeryxStripTelltale.local),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.tx),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.rx),
      KeryxTheme.ghostSegmentOpacity,
    );
  });

  testWidgets('TX lit uses amber, not the TX signal red', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(
        channel: 1,
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.tx},
      ),
    );
    expect(_opacityFor(tester, KeryxStripTelltale.tx), 1);
    expect(_telltaleColor(tester, KeryxStripTelltale.tx), KeryxTheme.lcd);
    expect(_telltaleColor(tester, KeryxStripTelltale.tx), isNot(KeryxTheme.tx));
    expect(
      _opacityFor(tester, KeryxStripTelltale.local),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.linked),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.rx),
      KeryxTheme.ghostSegmentOpacity,
    );
  });

  testWidgets('RX lit, others ghost', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(
        channel: 1,
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.rx},
      ),
    );
    expect(_opacityFor(tester, KeryxStripTelltale.rx), 1);
    expect(_telltaleColor(tester, KeryxStripTelltale.rx), KeryxTheme.lcd);
    expect(
      _opacityFor(tester, KeryxStripTelltale.local),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.linked),
      KeryxTheme.ghostSegmentOpacity,
    );
    expect(
      _opacityFor(tester, KeryxStripTelltale.tx),
      KeryxTheme.ghostSegmentOpacity,
    );
  });

  testWidgets('all-ghost idle: every telltale at ghostSegmentOpacity', (
    tester,
  ) async {
    await pumpDisplay(tester, const KeryxDisplayModel(channel: 1));
    for (final indicator in KeryxStripTelltale.values) {
      expect(_opacityFor(tester, indicator), KeryxTheme.ghostSegmentOpacity);
    }
  });

  testWidgets('status line CHANNEL CLEAR', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(channel: 1, statusLine: 'CHANNEL CLEAR'),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('keryx-lcd-secondary'))).data,
      'CHANNEL CLEAR',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('keryx-lcd-secondary')))
          .style!
          .fontFamily,
      'Share Tech Mono',
    );
  });

  testWidgets('status line TX 00:07', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(
        channel: 1,
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.tx},
        statusLine: 'TX 00:07',
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('keryx-lcd-secondary'))).data,
      'TX 00:07',
    );
  });

  testWidgets('status line RX <callsign>', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(
        channel: 1,
        telltales: <KeryxStripTelltale>{KeryxStripTelltale.rx},
        statusLine: 'RX BRAVO-7',
      ),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('keryx-lcd-secondary'))).data,
      'RX BRAVO-7',
    );
  });

  testWidgets('S-meter lights quality bars and ghosts the rest', (
    tester,
  ) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(channel: 1, signalQuality: 4),
    );
    for (var bar = 1; bar <= 9; bar++) {
      final box = tester.widget<Container>(
        find.byKey(Key('keryx-lcd-smeter-bar-$bar')),
      );
      final color = (box.decoration! as BoxDecoration).color;
      if (bar <= 4) {
        expect(color, KeryxTheme.rx);
      } else {
        expect(
          color,
          KeryxTheme.lcd.withValues(alpha: KeryxTheme.ghostSegmentOpacity),
        );
      }
    }
  });

  testWidgets('follows the supplied night-dimming level', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(channel: 1, dimLevel: 0.55),
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

  testWidgets('boot flash shows all-segments 88', (tester) async {
    await pumpDisplay(
      tester,
      const KeryxDisplayModel(channel: 1, isBooting: true),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('keryx-lcd-primary'))).data,
      '88',
    );
  });
}

double _opacityFor(WidgetTester tester, KeryxStripTelltale telltale) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(Key('keryx-lcd-telltale-${telltale.name}')),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

Color? _telltaleColor(WidgetTester tester, KeryxStripTelltale telltale) =>
    tester
        .widget<Text>(find.byKey(Key('keryx-lcd-telltale-${telltale.name}')))
        .style
        ?.color;
