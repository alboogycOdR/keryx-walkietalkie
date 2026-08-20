import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/ptt/edge_glow.dart';

void main() {
  testWidgets('opacity is 0 when inactive, 1 when active (DS §2)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PttEdgeGlow(active: false)),
    );
    var glow = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('keryx-ptt-edge-glow')),
    );
    expect(glow.opacity, 0);

    await tester.pumpWidget(
      const MaterialApp(home: PttEdgeGlow(active: true)),
    );
    await tester.pump(const Duration(milliseconds: 140));
    glow = tester.widget<AnimatedOpacity>(
      find.byKey(const Key('keryx-ptt-edge-glow')),
    );
    expect(glow.opacity, 1);
  });

  testWidgets('renders child content beneath the glow overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PttEdgeGlow(active: false, child: Text('face content')),
      ),
    );

    expect(find.text('face content'), findsOneWidget);
  });
}
