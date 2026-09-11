import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/state/radio_state.dart';
import 'package:keryx/core/state/radio_state_controller.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import '../features/talk/fake_radio_host.dart';

/// TASK-078 — shared pump for R2 shell regression tests (goldens, layout
/// matrix, overflow system-back). Duplicates the app-shell harness shape
/// rather than importing `test/app_shell/**` as a library.
Future<({FakeRadioHost host, ProviderContainer container})> pumpRegressionShell(
  WidgetTester tester, {
  Size size = const Size(360, 640),
  double textScale = 1.0,
  Brightness brightness = Brightness.dark,
  bool bootToIdle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  final host = FakeRadioHost();
  final container = ProviderContainer(
    overrides: <Override>[
      radioHostProvider.overrideWithValue(host),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: keryxUxThemeData(brightness: brightness),
        home: const MobileAppShell(),
      ),
    ),
  );
  // MobileAppShell.start() is deferred one microtask.
  await tester.pump();
  await tester.pumpAndSettle();

  if (bootToIdle) {
    container.read(radioStateProvider.notifier)
      ..dispatch(const PowerOn())
      ..dispatch(const BootCompleted());
    await tester.pumpAndSettle();
  }

  return (host: host, container: container);
}

Finder tabTalk() => find.byKey(ShellKeys.tabTalk);
Finder tabChannels() => find.byKey(ShellKeys.tabChannels);
Finder tabStations() => find.byKey(ShellKeys.tabStations);
Finder overflowMenu() => find.byKey(ShellKeys.overflowMenu);
Finder pttDisc() => find.byKey(const Key('keryx-talk-ptt-disc'));
