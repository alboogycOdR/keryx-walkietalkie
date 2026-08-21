import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/features/event_qr/event_link.dart';
import 'package:keryx/features/event_qr/qr_export_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

Widget _harness({
  EventLinkExpiryPreset initialPreset = defaultEventLinkExpiryPreset,
  DateTime Function()? now,
}) {
  return MaterialApp(
    home: Scaffold(
      body: EventQrExportScreen(
        payloadBuilder: (expiresAt) =>
            NumberedEventLink(region: 'za-cpt', channel: 7, code: 21, expiresAt: expiresAt),
        initialPreset: initialPreset,
        now: now,
      ),
    ),
  );
}

void main() {
  testWidgets('renders a QR image and the link text for the initial (default) preset', (
    tester,
  ) async {
    final fixedNow = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(_harness(now: () => fixedNow));

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('event_qr_link_text')), findsOneWidget);

    final textWidget = tester.widget<SelectableText>(find.byKey(const Key('event_qr_link_text')));
    final link = decodeEventLink(textWidget.data!, now: fixedNow) as EventLinkDecoded;
    expect((link.payload as NumberedEventLink).channel, 7);
    expect(link.payload.expiresAt, fixedNow.add(const Duration(hours: 24))); // 24h default
    expect(link.isExpired, isFalse);
  });

  testWidgets('selecting the 7-day preset updates the encoded link immediately', (tester) async {
    final fixedNow = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(_harness(now: () => fixedNow));

    await tester.tap(find.widgetWithText(ChoiceChip, '7 days'));
    await tester.pumpAndSettle();

    final textWidget = tester.widget<SelectableText>(find.byKey(const Key('event_qr_link_text')));
    final link = decodeEventLink(textWidget.data!, now: fixedNow) as EventLinkDecoded;
    expect(link.payload.expiresAt, fixedNow.add(const Duration(days: 7)));
  });

  testWidgets('no-expiry requires an explicit second tap before it takes effect (FR-044)', (
    tester,
  ) async {
    final fixedNow = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(_harness(now: () => fixedNow));

    await tester.tap(find.widgetWithText(ChoiceChip, 'No expiry'));
    await tester.pumpAndSettle();

    // First tap only arms confirmation — the link must still carry the
    // default 24h expiry, not no-expiry, until confirmed.
    var textWidget = tester.widget<SelectableText>(find.byKey(const Key('event_qr_link_text')));
    var link = decodeEventLink(textWidget.data!, now: fixedNow) as EventLinkDecoded;
    expect(link.payload.expiresAt, isNotNull);
    expect(find.byKey(const Key('event_qr_confirm_no_expiry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('event_qr_confirm_no_expiry')));
    await tester.pumpAndSettle();

    textWidget = tester.widget<SelectableText>(find.byKey(const Key('event_qr_link_text')));
    link = decodeEventLink(textWidget.data!, now: fixedNow) as EventLinkDecoded;
    expect(link.payload.expiresAt, isNull);
    expect(find.byKey(const Key('event_qr_confirm_no_expiry')), findsNothing);
  });

  testWidgets('cancelling the no-expiry confirmation leaves the prior preset in effect', (
    tester,
  ) async {
    final fixedNow = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(_harness(now: () => fixedNow));

    await tester.tap(find.widgetWithText(ChoiceChip, 'No expiry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('event_qr_confirm_no_expiry')), findsNothing);
    final textWidget = tester.widget<SelectableText>(find.byKey(const Key('event_qr_link_text')));
    final link = decodeEventLink(textWidget.data!, now: fixedNow) as EventLinkDecoded;
    expect(link.payload.expiresAt, fixedNow.add(const Duration(hours: 24)));
  });
}
