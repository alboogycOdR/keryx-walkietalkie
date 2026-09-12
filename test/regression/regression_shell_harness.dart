import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/identity/identity.dart';
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
  // Deterministic seed so overflow → My code can render a real QR without
  // hitting flutter_secure_storage (V2-VT-029).
  final keyPair = await IdentityKeyPair.fromSeed(List<int>.filled(32, 1));
  final container = ProviderContainer(
    overrides: <Override>[
      radioHostProvider.overrideWithValue(host),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      // v2 (TASK-093): identityProvider's production default hits the real
      // flutter_secure_storage platform channel, which never replies under
      // `flutter test` — every pumpAndSettle here hangs without this stub.
      // Mirrors test/app_shell/shell_harness.dart's own override.
      identityProvider.overrideWith(
        (ref) async => DeviceIdentity(
          installUuid: '00000000-0000-4000-8000-000000000000',
          peerId: 'stub-peer',
          callsign: Callsign.parse('STUB-1'),
          keyPair: keyPair,
        ),
      ),
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
Finder tabContacts() => find.byKey(ShellKeys.tabContacts);
Finder tabGroups() => find.byKey(ShellKeys.tabGroups);
Finder overflowMenu() => find.byKey(ShellKeys.overflowMenu);
Finder pttDisc() => find.byKey(const Key('keryx-talk-ptt-disc'));
