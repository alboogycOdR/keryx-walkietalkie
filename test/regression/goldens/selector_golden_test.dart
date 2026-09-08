import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channel_selector/channel_selector_screen.dart';

import '../../app_shell/fake_radio_host.dart';

/// TASK-058 — Verification §6: golden fixture for the channel selector,
/// dark and light.
void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = FakeRadioHost();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: ChannelSelectorScreen(host: host),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChannelSelectorScreen),
      matchesGoldenFile('goldens/selector_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('Channel selector ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: suffix, brightness: brightness);
    });
  }
}
