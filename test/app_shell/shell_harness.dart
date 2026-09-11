import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keryx/app_shell/app_shell.dart';
import 'package:keryx/core/settings/settings_repository.dart';
import 'package:keryx/core/theme/ux_tokens.dart';

import 'fake_radio_host.dart';

/// Maps a tab strip label to its `ShellKeys` — icon-only R2 tabs carry no
/// on-screen text (only a `Semantics`/`Tooltip` label), so tests address
/// them by key rather than by visible copy.
const Map<String, Key> _tabKeysByLabel = <String, Key>{
  'Talk': ShellKeys.tabTalk,
  'Channels': ShellKeys.tabChannels,
  'Stations': ShellKeys.tabStations,
};

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

/// R2 top tab strip destination, by label ("Talk"/"Channels"/"Stations") —
/// resolved through `ShellKeys` since the icon-only tabs carry no visible
/// text (TASK-077, ADR-002 §3 A1 replaces the old bottom `NavigationBar`).
Finder navDestination(String label) {
  final Key? key = _tabKeysByLabel[label];
  assert(key != null, 'no shell tab strip destination named "$label"');
  return find.byKey(key!);
}

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
