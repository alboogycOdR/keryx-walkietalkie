import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/my_code/my_code.dart';

Widget _app(Widget home, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: keryxUxThemeData(brightness: brightness),
    home: home,
  );
}

void main() {
  late IdentityKeyPair keys;

  setUp(() async {
    keys = await IdentityKeyPair.fromSeed(List<int>.filled(32, 3));
  });

  testWidgets('QR data is the ID payload and share link matches §3.1', (
    tester,
  ) async {
    final link = KeryxIdLink(callsign: 'SIERRA-19', publicKey: keys.publicKey);
    String? shared;
    await tester.pumpWidget(
      _app(
        MyCodeScreen(
          callsign: 'SIERRA-19',
          publicKey: keys.publicKey,
          brightness: const NoopScreenBrightness(),
          onShare: (url) async => shared = url,
        ),
      ),
    );
    final qr = tester.widget<KeryxIdQr>(find.byType(KeryxIdQr));
    expect(qr.payload, link.qrPayload);
    final decoded = KeryxIdLink.parse(qr.payload);
    expect(decoded.publicKey, keys.publicKey);
    expect(decoded.callsign, 'SIERRA-19');

    expect(find.text(link.displayId), findsOneWidget);

    await tester.tap(find.byKey(MyCodeKeys.share));
    await tester.pump();
    expect(shared, link.shareUrl);
  });

  testWidgets('copy writes the share URL', (tester) async {
    String? copied;
    final link = KeryxIdLink(callsign: 'BEN', publicKey: keys.publicKey);
    await tester.pumpWidget(
      _app(
        MyCodeScreen(
          callsign: 'BEN',
          publicKey: keys.publicKey,
          brightness: const NoopScreenBrightness(),
          clipboard: (text) async => copied = text,
        ),
      ),
    );
    await tester.tap(find.byKey(MyCodeKeys.copy));
    await tester.pump();
    expect(copied, link.shareUrl);
    expect(find.text(MyCodeCopy.copied), findsOneWidget);
  });

  testWidgets('brightness is raised while shown and restored on dispose', (
    tester,
  ) async {
    final brightness = RecordingScreenBrightness();
    await tester.pumpWidget(
      _app(
        MyCodeScreen(
          callsign: 'BEN',
          publicKey: keys.publicKey,
          brightness: brightness,
        ),
      ),
    );
    expect(brightness.setMaximumCount, 1);
    expect(brightness.restoreCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(brightness.restoreCount, 1);
  });
}
