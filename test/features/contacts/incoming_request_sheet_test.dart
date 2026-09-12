import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contact_view_models.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/contacts_keys.dart';
import 'package:keryx/features/contacts/incoming_request_sheet.dart';

void main() {
  const request = RequestRowVm(pk: 'in1', callsign: 'BEN', shortCode: '4R2M');

  testWidgets('shows Add CALLSIGN·CODE? and Accept/Decline/Block', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: const Scaffold(body: IncomingRequestSheet(request: request)),
      ),
    );

    expect(find.text(ContactsCopy.addRequestPrompt('BEN·4R2M')), findsOneWidget);
    expect(find.byKey(ContactsKeys.incomingAccept), findsOneWidget);
    expect(find.byKey(ContactsKeys.incomingDecline), findsOneWidget);
    expect(find.byKey(ContactsKeys.incomingBlock), findsOneWidget);
  });

  testWidgets('Block requires a second tap before firing', (tester) async {
    var blocked = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Scaffold(
          body: IncomingRequestSheet(request: request, onBlock: () => blocked++),
        ),
      ),
    );

    await tester.tap(find.byKey(ContactsKeys.incomingBlock));
    await tester.pump();
    expect(blocked, 0);
    expect(find.text(ContactsCopy.blockConfirmAction), findsOneWidget);

    await tester.tap(find.byKey(ContactsKeys.incomingBlock));
    await tester.pump();
    expect(blocked, 1);
  });
}
