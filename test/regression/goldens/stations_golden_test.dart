import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/stations/stations_screen.dart';
import 'package:keryx/services/session/session.dart' show StationInfo;

import '../../app_shell/fake_radio_host.dart';

/// TASK-058 — Verification §6: golden fixtures for "Stations empty/
/// populated", dark and light.
void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required List<StationInfo> stations,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = FakeRadioHost();
    host.emit(RadioHostSnapshot(stations: stations));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: const StationsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(StationsScreen),
      matchesGoldenFile('goldens/stations_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Stations — empty ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'empty_$suffix',
        brightness: brightness,
        stations: const <StationInfo>[],
      );
    });

    testWidgets('Stations — populated ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'populated_$suffix',
        brightness: brightness,
        stations: const <StationInfo>[
          StationInfo(peerId: 'peer-a', callsign: 'ALPHA-1'),
          StationInfo(peerId: 'peer-b', callsign: 'BRAVO-2'),
        ],
      );
    });
  }
}
