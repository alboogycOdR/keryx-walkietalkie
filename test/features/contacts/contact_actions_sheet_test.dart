import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contact_actions_sheet.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/contacts_keys.dart';

const _contact = ContactRowVm(
  pk: 'ada',
  callsign: 'Ada',
  shortCode: '4R2M',
  visual: PresenceVisual.available,
);

void main() {
  testWidgets('Alert is disabled for 10 minutes after use', (tester) async {
    var alerts = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: const Scaffold(
          body: ContactActionsSheet(contact: _contact, alertDisabled: true),
        ),
      ),
    );

    expect(find.text(ContactsCopy.alertCooldown), findsOneWidget);
    await tester.tap(find.byKey(ContactsKeys.actionsAlert));
    expect(alerts, 0);
  });

  testWidgets('Block requires a second tap; Alert and Remove fire on first', (tester) async {
    var alerts = 0;
    var removes = 0;
    var blocks = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Scaffold(
          body: ContactActionsSheet(
            contact: _contact,
            onAlert: () => alerts++,
            onRemove: () => removes++,
            onBlock: () => blocks++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(ContactsKeys.actionsBlock));
    await tester.pump();
    expect(blocks, 0);
    expect(find.text(ContactsCopy.blockConfirmAction), findsOneWidget);

    await tester.tap(find.byKey(ContactsKeys.actionsBlock));
    await tester.pump();
    expect(blocks, 1);
  });
}
