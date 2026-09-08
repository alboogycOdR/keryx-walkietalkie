import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/identity/identity.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/settings/settings_screen.dart';

import '../../app_shell/fake_radio_host.dart';
import '../../core/identity/memory_identity_store.dart';

/// TASK-058 — Verification §6: golden fixture for Settings, dark and light.
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
    // Seeded, not empty: an empty store makes `IdentityRepository` mint a
    // random UUID/NATO callsign on first read (`Random.secure()`), which
    // would render different text on every run and make this golden
    // non-deterministic (observed: 0.01% pixel diff on a bare re-run).
    final identityStore = MemoryIdentityStore(<String, String>{
      'keryx.identity.install_uuid': '00000000-0000-4000-8000-000000000000',
      'keryx.identity.callsign': 'GOLDEN-1',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: SettingsScreen(
            identityRepository: IdentityRepository(identityStore),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('goldens/settings_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';
    testWidgets('Settings ($suffix)', (tester) async {
      await pumpAndGolden(tester, name: suffix, brightness: brightness);
    });
  }
}
