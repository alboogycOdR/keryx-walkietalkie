import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'fake_radio_host.dart';

/// Shared pump for `lib/app_shell/**` widget tests — fake host + in-memory
/// settings, successor theme, phone-sized surface so ListView actions
/// (Select channel, Stations QR) stay on-screen.
Widget pumpShell({
  required FakeRadioHost host,
  required Widget home,
  ThemeData? theme,
}) {
  return ProviderScope(
    overrides: <Override>[
      radioHostProvider.overrideWithValue(host),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
    ],
    child: MaterialApp(theme: theme ?? keryxUxThemeData(), home: home),
  );
}

void givePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// NavigationBar destination label — not the Settings AppBar title.
Finder navDestination(String label) => find.descendant(
  of: find.byType(NavigationBar),
  matching: find.text(label),
);

/// Pop the route that owns [screen]. `WidgetTester.pageBack` looks up
/// tooltip "Back" globally and fails when Talk's header Back and a
/// pushed screen's AppBar Back are both on stage (or when two nested
/// navigators each imply a leading).
Future<void> popScreen(
  WidgetTester tester,
  Finder screen, {
  bool settle = true,
}) async {
  final BuildContext context = tester.element(screen);
  Navigator.of(context).pop();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}
