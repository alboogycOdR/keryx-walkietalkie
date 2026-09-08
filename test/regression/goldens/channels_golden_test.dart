import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/radio_host_provider.dart';
import 'package:keryx/core/radio_host/radio_host.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';
import 'package:keryx/features/channels/channels.dart';

import '../../features/channels/fake_radio_host.dart';

/// TASK-058 — Verification §6: golden fixtures for "Channels empty/
/// populated", dark and light.
///
/// A from-scratch, task-owned equivalent of
/// `test/features/channels/channels_landing_test.dart`'s own
/// `SeededRadioStateController` (that file's class is a top-level, but this
/// task's own copy avoids depending on another task's `_test.dart` file).
class _SeededRadioStateController extends RadioStateController {
  _SeededRadioStateController(this._seed);
  final RadioState _seed;

  @override
  RadioState build() => _seed;
}

void main() {
  Future<void> pumpAndGolden(
    WidgetTester tester, {
    required String name,
    required Brightness brightness,
    required List<TunedChannel> channelMemory,
  }) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = FakeRadioHost();
    host.emit(RadioHostSnapshot(channelMemory: channelMemory));

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          radioHostProvider.overrideWithValue(host),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          radioStateProvider.overrideWith(
            () => _SeededRadioStateController(
              const RadioState(phase: RadioPhase.idle, mode: RadioMode.local),
            ),
          ),
        ],
        child: MaterialApp(
          theme: keryxUxThemeData(brightness: brightness),
          home: ChannelsLanding(
            onOpenTalk: () {},
            onSelectChannel: () {},
            persistentNavigation: NavigationBar(
              selectedIndex: 0,
              destinations: const <NavigationDestination>[
                NavigationDestination(icon: Icon(Icons.radio), label: 'Channels'),
                NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ChannelsLanding),
      matchesGoldenFile('goldens/channels_$name.png'),
    );
  }

  for (final brightness in <Brightness>[Brightness.dark, Brightness.light]) {
    final String suffix = brightness == Brightness.dark ? 'dark' : 'light';

    testWidgets('Channels — empty recall ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'empty_$suffix',
        brightness: brightness,
        channelMemory: const <TunedChannel>[],
      );
    });

    testWidgets('Channels — populated recall ($suffix)', (tester) async {
      await pumpAndGolden(
        tester,
        name: 'populated_$suffix',
        brightness: brightness,
        channelMemory: const <TunedChannel>[
          TunedChannel(channel: 7, privacyCode: 3),
          TunedChannel(channel: 12, privacyCode: 1),
          TunedChannel(channel: 42, privacyCode: 0),
        ],
      );
    });
  }
}
