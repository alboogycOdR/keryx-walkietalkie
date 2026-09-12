import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/add_contact_sheet.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/contacts_keys.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

void main() {
  testWidgets('paste of a tampered ID is refused locally and never calls onPaste', (tester) async {
    var pasteCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Scaffold(
          body: AddContactSheet(
            onPaste: (raw) async {
              pasteCalls++;
              return null;
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(ContactsKeys.addPasteField), 'keryx://id?v=1&c=BEN&k=nope');
    await tester.tap(find.byKey(ContactsKeys.addPasteSubmit));
    await tester.pump();

    expect(find.text(ContactsCopy.tamperedId), findsOneWidget);
    expect(pasteCalls, 0);
  });

  testWidgets('paste of a valid ID is forwarded to onPaste', (tester) async {
    final pasted = <String>[];
    final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Scaffold(
          body: AddContactSheet(
            onPaste: (raw) async {
              pasted.add(raw);
              return null;
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(ContactsKeys.addPasteField), link.qrPayload);
    await tester.tap(find.byKey(ContactsKeys.addPasteSubmit));
    await tester.pump();

    expect(pasted, [link.qrPayload]);
  });

  testWidgets('Scan a code and Show my code fire their callbacks', (tester) async {
    var scanned = false;
    var shown = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Scaffold(
          body: AddContactSheet(
            onScan: () => scanned = true,
            onShowMyCode: () => shown = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(ContactsKeys.addScan));
    expect(scanned, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Scaffold(
          body: AddContactSheet(
            onScan: () => scanned = true,
            onShowMyCode: () => shown = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(ContactsKeys.addShowMyCode));
    expect(shown, isTrue);
  });
}
