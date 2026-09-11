import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/talk/talk_screen.dart' as talkui;

import 'regression_shell_harness.dart';

/// TASK-078 — Verification §6 layout matrix against the assembled R2 shell
/// (not a per-screen fake): 320×568, 360×640, 412×915 at text scale 1.0 and
/// 2.0, plus landscape 640×360. Asserts no overflow, a reachable PTT, and
/// reachable tab strip + overflow menu.
class _LayoutCase {
  const _LayoutCase(this.label, this.size, {this.textScale = 1.0});

  final String label;
  final Size size;
  final double textScale;
}

const List<_LayoutCase> _matrix = <_LayoutCase>[
  _LayoutCase('320×568 @ 1.0', Size(320, 568)),
  _LayoutCase('320×568 @ 2.0', Size(320, 568), textScale: 2.0),
  _LayoutCase('360×640 @ 1.0', Size(360, 640)),
  _LayoutCase('360×640 @ 2.0', Size(360, 640), textScale: 2.0),
  _LayoutCase('412×915 @ 1.0', Size(412, 915)),
  _LayoutCase('412×915 @ 2.0', Size(412, 915), textScale: 2.0),
  _LayoutCase('landscape 640×360', Size(640, 360)),
];

void main() {
  for (final _LayoutCase c in _matrix) {
    testWidgets('R2 shell layout — ${c.label}: no overflow, PTT and chrome '
        'reachable (Verification §6)', (tester) async {
      await pumpRegressionShell(tester, size: c.size, textScale: c.textScale);

      expect(
        tester.takeException(),
        isNull,
        reason: '${c.label} threw (overflow or other layout exception)',
      );

      expect(tabTalk(), findsOneWidget);
      expect(tabChannels(), findsOneWidget);
      expect(tabStations(), findsOneWidget);
      expect(overflowMenu(), findsOneWidget);
      await tester.ensureVisible(tabTalk());
      await tester.ensureVisible(overflowMenu());

      final Size talkTarget = tester.getSize(tabTalk());
      expect(
        talkTarget.width,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
        reason: '${c.label}: Talk tab width ${talkTarget.width}',
      );
      expect(
        talkTarget.height,
        greaterThanOrEqualTo(KeryxUxSpacing.minTarget),
        reason: '${c.label}: Talk tab height ${talkTarget.height}',
      );

      expect(find.byType(talkui.TalkScreen), findsOneWidget);
      expect(pttDisc(), findsOneWidget);
      // ADR-002 A3: at text scale 2.0 scrolling is allowed; reachable
      // means the disc can be brought on-stage, not that it starts there.
      await tester.ensureVisible(pttDisc());
      expect(
        tester.getSize(pttDisc()).shortestSide,
        greaterThanOrEqualTo(96),
        reason: '${c.label}: PTT below ADR-002 A3 96 dp floor',
      );

      if (c.label == '360×640 @ 1.0') {
        // ADR-002 A7: ring centred in the space below the channel card.
        final Rect card = tester.getRect(
          find.byKey(const Key('keryx-talk-channel-card')),
        );
        final Rect ring = tester.getRect(pttDisc());
        final Rect talk = tester.getRect(find.byType(talkui.TalkScreen));
        final double remainingMid = (card.bottom + talk.bottom) / 2;
        expect(
          (ring.center.dy - remainingMid).abs(),
          lessThanOrEqualTo(c.size.height * 0.10),
          reason:
              '${c.label}: PTT centre ${ring.center.dy} vs remaining '
              'mid $remainingMid (card.bottom=${card.bottom}, '
              'talk.bottom=${talk.bottom})',
        );
      }
    });
  }
}
