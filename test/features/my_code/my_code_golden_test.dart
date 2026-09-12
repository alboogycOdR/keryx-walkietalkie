import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/my_code/my_code.dart';

void main() {
  late IdentityKeyPair keys;

  setUp(() async {
    keys = await IdentityKeyPair.fromSeed(List<int>.filled(32, 1));
  });

  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: KeyedSubtree(
          key: const Key('my-code-golden-root'),
          child: MyCodeScreen(
            callsign: 'BEN',
            publicKey: keys.publicKey,
            brightness: const NoopScreenBrightness(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('my-code-golden-root')),
      matchesGoldenFile('goldens/my_code_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('My code golden ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: suffix, brightness: brightness);
    });
  }
}
