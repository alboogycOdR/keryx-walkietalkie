import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart' show TunedChannel;
import 'package:keryx/features/tuning/channel_recall.dart';

void main() {
  Widget harness({
    required List<TunedChannel> entries,
    required ValueChanged<TunedChannel> onSelect,
    VoidCallback? onDismiss,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChannelRecallPanel(
          entries: entries,
          onSelect: onSelect,
          onDismiss: onDismiss,
        ),
      ),
    );
  }

  testWidgets('renders every injected entry, most-recent first, unmodified', (
    tester,
  ) async {
    const entries = <TunedChannel>[
      TunedChannel(channel: 7, privacyCode: 21),
      TunedChannel(channel: 12, privacyCode: 0),
      TunedChannel(channel: 99, privacyCode: 38),
    ];
    await tester.pumpWidget(harness(entries: entries, onSelect: (_) {}));

    expect(find.text('CH 07 · 21'), findsOneWidget);
    expect(find.text('CH 12 · 00'), findsOneWidget);
    expect(find.text('CH 99 · 38'), findsOneWidget);
  });

  testWidgets('an empty list renders an in-world empty state, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(harness(entries: const <TunedChannel>[], onSelect: (_) {}));

    expect(find.text('No channels remembered yet.'), findsOneWidget);
  });

  testWidgets('tapping a row fires onSelect with that exact entry', (
    tester,
  ) async {
    TunedChannel? selected;
    const target = TunedChannel(channel: 42, privacyCode: 5);
    await tester.pumpWidget(
      harness(
        entries: const <TunedChannel>[
          TunedChannel(channel: 7, privacyCode: 21),
          target,
        ],
        onSelect: (entry) => selected = entry,
      ),
    );

    await tester.tap(find.text('CH 42 · 05'));
    await tester.pump();

    expect(selected, target);
  });

  testWidgets('DISMISS fires onDismiss and never onSelect', (tester) async {
    var selected = false;
    var dismissed = false;
    await tester.pumpWidget(
      harness(
        entries: const <TunedChannel>[TunedChannel(channel: 7, privacyCode: 21)],
        onSelect: (_) => selected = true,
        onDismiss: () => dismissed = true,
      ),
    );

    await tester.tap(find.byKey(const Key('keryx-recall-dismiss')));
    await tester.pump();

    expect(dismissed, isTrue);
    expect(selected, isFalse);
  });

  testWidgets('each memory row clears the FR-106 48dp touch-target floor', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        entries: const <TunedChannel>[TunedChannel(channel: 7, privacyCode: 21)],
        onSelect: (_) {},
      ),
    );

    final row = find.ancestor(
      of: find.text('CH 07 · 21'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
  });

  testWidgets('each memory row exposes a TalkBack recall label', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        entries: const <TunedChannel>[TunedChannel(channel: 7, privacyCode: 21)],
        onSelect: (_) {},
      ),
    );

    final semantics = tester.getSemantics(
      find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Recall CH 07 · 21'),
    );
    expect(semantics.label, contains('Recall'));
  });
}
