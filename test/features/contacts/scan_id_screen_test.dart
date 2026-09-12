import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/contacts/contacts_copy.dart';
import 'package:keryx/features/contacts/contacts_keys.dart';
import 'package:keryx/features/contacts/scan_id_screen.dart';
import 'package:keryx/features/my_code/keryx_id_link.dart';

Uint8List _key() => Uint8List.fromList(List<int>.generate(32, (i) => i + 1));

Widget _fakeScanner({required ValueChanged<String> onRaw, required String payload}) {
  return TextButton(
    key: const Key('fake-scan-emit'),
    onPressed: () => onRaw(payload),
    child: const Text('emit'),
  );
}

void main() {
  testWidgets('a valid scan is forwarded and the screen pops', (tester) async {
    final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
    final received = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ScanIdScreen(
                    onRaw: received.add,
                    scannerBuilder: ({required onRaw}) => _fakeScanner(onRaw: onRaw, payload: link.qrPayload),
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('fake-scan-emit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(received, [link.qrPayload]);
    expect(find.byKey(ContactsKeys.scanScreen), findsNothing);
  });

  testWidgets('a tampered scan is refused locally and never forwarded', (tester) async {
    final received = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: ScanIdScreen(
          onRaw: received.add,
          scannerBuilder: ({required onRaw}) =>
              _fakeScanner(onRaw: onRaw, payload: 'keryx://id?v=1&c=BEN&k=nope'),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fake-scan-emit')));
    await tester.pump();

    expect(received, isEmpty);
    expect(find.text(ContactsCopy.tamperedId), findsOneWidget);
  });
}
