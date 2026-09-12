import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/presence_badge.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: keryxUxThemeData(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('every status exposes its word to TalkBack', (tester) async {
    for (final visual in PresenceVisual.values) {
      final word = presenceWord(visual);
      await tester.pumpWidget(
        _wrap(PresenceBadge(visual: visual, label: word, semanticLabel: word)),
      );
      expect(tester.getSemantics(find.byType(PresenceBadge)).label, word);
    }
  });

  testWidgets('Nearby and Talking add their words next to the status', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PresenceBadge(
          visual: PresenceVisual.available,
          label: ContactsCopy.availableLabel,
          isNearby: true,
          isTalking: true,
        ),
      ),
    );
    expect(find.text(ContactsCopy.availableLabel), findsOneWidget);
    expect(find.text(ContactsCopy.nearbyLabel), findsOneWidget);
    expect(find.text(ContactsCopy.talkingLabel), findsOneWidget);
    expect(find.byIcon(Icons.wifi), findsOneWidget);
  });
}
