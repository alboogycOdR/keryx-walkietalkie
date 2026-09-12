import 'dart:async';
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
                    onRaw: (raw) async {
                      received.add(raw);
                      return null;
                    },
                    scannerBuilder: ({required onRaw}) =>
                        _fakeScanner(onRaw: onRaw, payload: link.qrPayload),
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
          onRaw: (raw) async {
            received.add(raw);
            return null;
          },
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

  testWidgets('a send failure stays on the scan screen with the paste-path error', (
    tester,
  ) async {
    final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: ScanIdScreen(
          onRaw: (raw) async => throw StateError('directory unreachable'),
          scannerBuilder: ({required onRaw}) =>
              _fakeScanner(onRaw: onRaw, payload: link.qrPayload),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('fake-scan-emit')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(ContactsKeys.scanScreen), findsOneWidget);
    expect(find.text(ContactsCopy.requestFailed), findsOneWidget);
  });

  testWidgets('the scan screen does not pop while the request is still in flight', (
    tester,
  ) async {
    final link = KeryxIdLink(callsign: 'BEN', publicKey: _key());
    final pending = Completer<String?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => ScanIdScreen(
                    onRaw: (_) => pending.future,
                    scannerBuilder: ({required onRaw}) =>
                        _fakeScanner(onRaw: onRaw, payload: link.qrPayload),
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

    expect(find.byKey(ContactsKeys.scanScreen), findsOneWidget);
    expect(find.byKey(ContactsKeys.scanBusy), findsOneWidget);

    pending.complete(ContactsCopy.requestFailed);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(ContactsKeys.scanScreen), findsOneWidget);
    expect(find.text(ContactsCopy.requestFailed), findsOneWidget);
  });

  testWidgets('forceLocalOnly shows a dismissable contacts/presence warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(),
        home: ScanIdScreen(
          forceLocalOnly: true,
          onRaw: (_) async => null,
          scannerBuilder: ({required onRaw}) =>
              _fakeScanner(onRaw: onRaw, payload: 'unused'),
        ),
      ),
    );

    expect(find.byKey(ContactsKeys.localOnlyNotice), findsOneWidget);
    expect(find.text(ContactsCopy.localOnlyWarning), findsOneWidget);

    await tester.tap(find.byKey(ContactsKeys.localOnlyNoticeDismiss));
    await tester.pump();

    expect(find.byKey(ContactsKeys.localOnlyNotice), findsNothing);
  });
}
