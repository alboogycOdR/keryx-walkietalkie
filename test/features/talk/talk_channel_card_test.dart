import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/presentation/connection_condition.dart';
import 'package:keryx/core/state/radio_state.dart' show RadioMode;
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/talk/talk_channel_card.dart';

/// TASK-074 — ADR-002 §3 A2's channel card, isolated from the rest of
/// `TalkScreen` (Technical §7 configured-vs-effective route).
void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: keryxUxThemeData(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('shows CH NN · CC and the effective route only (configured '
      'omitted when it matches)', (tester) async {
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 7,
          privacyCode: 3,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.local,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
          stationCountLabel: '3 stations',
          onOpenPicker: () {},
          onOpenStations: () {},
        ),
      ),
    );

    expect(find.text('CH 07 · 03'), findsOneWidget);
    expect(find.textContaining('LOCAL'), findsOneWidget);
    expect(find.textContaining('Configured'), findsNothing);
  });

  testWidgets('shows the configured mode only when it differs from the '
      'effective route (Technical §7)', (tester) async {
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 12,
          privacyCode: 0,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.auto,
            effectiveRoute: RadioMode.linked,
            degraded: false,
          ),
          stationCountLabel: '0 stations',
          onOpenPicker: () {},
          onOpenStations: () {},
        ),
      ),
    );

    expect(find.textContaining('Route LINKED'), findsOneWidget);
    expect(find.textContaining('Configured AUTO'), findsOneWidget);
  });

  testWidgets('unresolved effective route is Connecting, never AUTO; '
      'configured AUTO still shows (Technical §7)', (tester) async {
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 1,
          privacyCode: 0,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.auto,
            effectiveRoute: RadioMode.auto,
            degraded: false,
          ),
          stationCountLabel: '0 stations',
        ),
      ),
    );

    expect(find.textContaining('Route Connecting'), findsOneWidget);
    expect(find.textContaining('Configured AUTO'), findsOneWidget);
    expect(find.textContaining('Route AUTO'), findsNothing);
  });

  testWidgets('resolved LOCAL with configured AUTO keeps both labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 1,
          privacyCode: 0,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.auto,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
          stationCountLabel: '0 stations',
        ),
      ),
    );

    expect(find.textContaining('Route LOCAL'), findsOneWidget);
    expect(find.textContaining('Configured AUTO'), findsOneWidget);
  });

  testWidgets('the station-count chip fires onOpenStations and the picker '
      'button fires onOpenPicker', (tester) async {
    var stationsTaps = 0;
    var pickerTaps = 0;
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 1,
          privacyCode: 0,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.local,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
          stationCountLabel: '2 stations',
          onOpenStations: () => stationsTaps++,
          onOpenPicker: () => pickerTaps++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-talk-stations')));
    await tester.pump();
    expect(stationsTaps, 1);

    await tester.tap(find.byKey(const Key('keryx-talk-picker')));
    await tester.pump();
    expect(pickerTaps, 1);
  });

  testWidgets('the radio-controls tune icon is absent when its callback is '
      'null (ADR-002 A2)', (tester) async {
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 1,
          privacyCode: 0,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.local,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
          stationCountLabel: '0 stations',
        ),
      ),
    );

    expect(find.byKey(const Key('keryx-talk-radio-controls')), findsNothing);
  });

  testWidgets('the radio-controls tune icon renders and fires its callback '
      'when non-null (ADR-002 A2)', (tester) async {
    var radioControlsTaps = 0;
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 1,
          privacyCode: 0,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.local,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
          stationCountLabel: '0 stations',
          onOpenRadioControls: () => radioControlsTaps++,
        ),
      ),
    );

    expect(find.byKey(const Key('keryx-talk-radio-controls')), findsOneWidget);
    await tester.tap(find.byKey(const Key('keryx-talk-radio-controls')));
    await tester.pump();
    expect(radioControlsTaps, 1);
  });

  testWidgets('every tap target meets the 48dp minimum', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(
        TalkChannelCard(
          channel: 7,
          privacyCode: 3,
          connection: const ConnectionCondition(
            configuredMode: RadioMode.local,
            effectiveRoute: RadioMode.local,
            degraded: false,
          ),
          stationCountLabel: '3 stations',
          onOpenPicker: () {},
          onOpenStations: () {},
          onOpenRadioControls: () {},
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
